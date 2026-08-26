//
//  DrivingDetector.swift
//  MyTrack
//
//  State machine that turns raw Core Motion activity samples into
//  start/discard/stop decisions for an automatic trip, driving the shared
//  TripRecorder. GPS starts the instant automotive activity is first seen;
//  if driving doesn't last 60s the trip is discarded as noise. Past that
//  point, ending requires 5 minutes of continuous non-automotive activity,
//  and GPS keeps running through that window so the route isn't cut if
//  driving resumes (traffic light, ferry, etc).
//
//  Core Motion only reports activity *changes*, so no decision may rely on a
//  further sample arriving: a steady drive can produce a single automotive
//  sample, and a parked phone left perfectly still produces none at all. Every
//  deadline below is therefore evaluated against wall-clock time and re-armed
//  on a timer, never counted in samples.
//

import Foundation
import OSLog
import CoreLocation
import CoreMotion
import SwiftData
import Observation

@Observable
final class DrivingDetector {
    private let motionActivityService: MotionActivityService
    private let tripRecorder: TripRecorder
    private let vehicleService: VehicleService
    private let notificationService: NotificationService
    private let locationService: LocationService
    private let modelContext: ModelContext

    private(set) var isEnabled: Bool

    /// Set only while *this* detector owns the trip being recorded, so a trip
    /// the user started by hand is never silently finalized — nor notified
    /// about as if it had been detected automatically.
    private var recordingStartedAt: Date?
    private var stopCandidateSince: Date?
    private var pendingDecisionTask: Task<Void, Never>?
    private var isMonitoring = false

    /// "Always" is only reachable in two steps — the initial When In Use-style
    /// prompt, then a separate upgrade prompt once that's granted. Set for the
    /// duration of one enable() call so both are chained automatically instead
    /// of requiring the user to come back and enable again after each prompt.
    /// Not re-armed on relaunch, so declining the upgrade once doesn't turn
    /// into a repeated system prompt on every future cold start.
    private var isEscalatingToAlways = false
    private var lastEscalationRequestStatus: CLAuthorizationStatus?

    private static let startValidationWindow: TimeInterval = 60
    private static let stopConfirmationWindow: TimeInterval = 300
    /// How long non-automotive activity must persist before a trip too short to
    /// be validated is thrown away. Without it, a red light 30 seconds after
    /// departure would discard a real trip that is only just starting.
    private static let discardGraceWindow: TimeInterval = 60
    private static let preferenceKey = "isAutoDetectionEnabled"

    init(
        motionActivityService: MotionActivityService,
        tripRecorder: TripRecorder,
        vehicleService: VehicleService,
        notificationService: NotificationService,
        locationService: LocationService,
        modelContext: ModelContext
    ) {
        self.motionActivityService = motionActivityService
        self.tripRecorder = tripRecorder
        self.vehicleService = vehicleService
        self.notificationService = notificationService
        self.locationService = locationService
        self.modelContext = modelContext
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)

        // "Always" location can be granted or revoked from Settings while the
        // app isn't running, so monitoring is re-evaluated on every change
        // rather than trusting the status seen at launch.
        locationService.onAuthorizationChange = { [weak self] _ in
            self?.escalateToAlwaysIfNeeded()
            self?.startMonitoringIfPossible()
        }

        // Re-arms monitoring on every fresh process start — normal relaunch
        // after a force-quit, or a background relaunch triggered by a
        // significant location change — since isEnabled always starts false
        // in a brand new instance otherwise.
        if isEnabled {
            startMonitoringIfPossible()
        }
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.preferenceKey)
        isEscalatingToAlways = true
        lastEscalationRequestStatus = nil
        escalateToAlwaysIfNeeded()
        startMonitoringIfPossible()
    }

    /// Stops watching motion activity. A trip already in progress is left
    /// running — TripRecorder keeps recording it via the manual-mode path
    /// until finalized, rather than being cut off abruptly.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.preferenceKey)
        isEscalatingToAlways = false
        stopMonitoring()
        resetState()
    }

    /// The moment driving actually stopped for the trip this detector owns, if
    /// it has stopped but isn't finalized yet. Lets a stop triggered from the
    /// app end the trip where the driving ended, rather than padding it with
    /// the minutes spent parked inside the stop-confirmation window.
    var ownedTripDrivingStoppedAt: Date? {
        recordingStartedAt == nil ? nil : stopCandidateSince
    }

    /// Call when the trip this detector started was ended from somewhere else —
    /// the user tapping Stop in the app. Without it the leftover state would
    /// later attach itself to a trip the user starts by hand, and finalize that
    /// one behind their back.
    func forgetOwnedTrip() {
        resetState()
    }

    /// Chains the two system prompts needed to reach "Always" — see
    /// isEscalatingToAlways — deduplicated per status so a re-delivered
    /// authorization callback for the same status doesn't re-show a prompt
    /// the user just answered.
    private func escalateToAlwaysIfNeeded() {
        guard isEscalatingToAlways else { return }
        let status = locationService.authorizationStatus

        switch status {
        case .notDetermined, .authorizedWhenInUse:
            guard lastEscalationRequestStatus != status else { return }
            lastEscalationRequestStatus = status
            locationService.requestAlwaysAuthorization()
        default:
            // Reached "Always", or the user declined outright — either way
            // there is nothing left to escalate toward.
            isEscalatingToAlways = false
        }
    }

    /// Arms monitoring only when it can actually work. Without "Always" the app
    /// is never woken to see driving start, and without a motion coprocessor no
    /// activity sample is ever delivered — in both cases starting would leave
    /// the toggle looking active while recording nothing.
    private func startMonitoringIfPossible() {
        guard isEnabled, !isMonitoring else { return }
        guard locationService.authorizationStatus == .authorizedAlways else {
            AppLog.recording.notice("Auto-detection is on but \"Always\" location isn't granted — monitoring stays off.")
            return
        }
        guard motionActivityService.isAvailable else {
            AppLog.recording.notice("Motion activity is unavailable on this device — auto-detection can't run.")
            return
        }

        isMonitoring = true
        locationService.startSignificantLocationMonitoring()
        motionActivityService.startMonitoring { [weak self] activity in
            self?.handle(activity)
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        locationService.stopSignificantLocationMonitoring()
        motionActivityService.stopMonitoring()
    }

    private func resetState() {
        recordingStartedAt = nil
        clearPendingDecision()
    }

    private func handle(_ activity: CMMotionActivity) {
        guard activity.confidence != .low else { return }

        if activity.automotive {
            // Driving (again): any pending stop or discard decision is off.
            clearPendingDecision()
            if !tripRecorder.isRecording {
                startProvisionalTrip()
            }
            return
        }

        // This detector only ends trips it started itself: a manual recording
        // belongs to the user until they stop it by hand.
        guard recordingStartedAt != nil, tripRecorder.isRecording else { return }

        if stopCandidateSince == nil {
            stopCandidateSince = Date()
        }
        evaluatePendingDecision()
    }

    /// Decides what to do with a trip whose driving activity has stopped.
    /// Runs both on each new activity sample and from a timer, because a
    /// stopped phone may never produce another sample: without the timer a
    /// trip could stay open — GPS running — indefinitely.
    private func evaluatePendingDecision() {
        guard let startedAt = recordingStartedAt,
              let candidateStart = stopCandidateSince,
              tripRecorder.isRecording
        else {
            return
        }

        let drivenDuration = candidateStart.timeIntervalSince(startedAt)
        let stoppedFor = Date().timeIntervalSince(candidateStart)

        guard drivenDuration >= Self.startValidationWindow else {
            // Too short to be a real trip yet — but wait out the grace window
            // in case driving simply paused rather than ended.
            if stoppedFor >= Self.discardGraceWindow {
                AppLog.recording.notice("Discarding an automatic trip: driving lasted under the validation window.")
                tripRecorder.discard()
                resetState()
            } else {
                scheduleDecision(after: Self.discardGraceWindow - stoppedFor)
            }
            return
        }

        if stoppedFor >= Self.stopConfirmationWindow {
            finalizeTrip(endDate: candidateStart)
        } else {
            scheduleDecision(after: Self.stopConfirmationWindow - stoppedFor)
        }
    }

    private func scheduleDecision(after delay: TimeInterval) {
        pendingDecisionTask?.cancel()
        pendingDecisionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 1)))
            guard !Task.isCancelled else { return }
            self?.evaluatePendingDecision()
        }
    }

    private func clearPendingDecision() {
        pendingDecisionTask?.cancel()
        pendingDecisionTask = nil
        stopCandidateSince = nil
    }

    private func startProvisionalTrip() {
        let vehicle = vehicleService.selectedVehicle(in: modelContext)
        tripRecorder.start(vehicle: vehicle, source: .automatic)
        // Recording can refuse to start (location authorization lost since
        // monitoring was armed); claiming ownership of a trip that doesn't
        // exist would leave this detector waiting on it forever.
        guard tripRecorder.isRecording else { return }

        recordingStartedAt = Date()
        clearPendingDecision()
    }

    private func finalizeTrip(endDate: Date) {
        // A trip without a single GPS point has no route and no distance —
        // permission revoked mid-trip, or no signal the whole way. There is
        // nothing to show or confirm, so drop it rather than asking the user
        // about a 0 km trip.
        guard tripRecorder.hasRecordedRoutePoints else {
            AppLog.recording.notice("Discarding an automatic trip that recorded no GPS point.")
            tripRecorder.discard()
            resetState()
            return
        }

        if let trip = tripRecorder.finalize(endDate: endDate) {
            notificationService.scheduleTripConfirmationNotification(for: trip)
        }
        resetState()
    }
}
