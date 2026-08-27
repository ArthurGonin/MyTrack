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

/// Why automatic detection is or isn't actually running. `isEnabled` alone
/// only records that the user asked for it — monitoring can still be
/// impossible, and saying so is the difference between a setting that works
/// and one that lies.
enum DrivingDetectionStatus: Equatable {
    /// The user hasn't asked for automatic detection.
    case off
    /// Asked for, and actually watching.
    case running
    /// Asked for, but "Always" location isn't granted — the app is then never
    /// woken to see a drive start.
    case needsAlwaysLocation
    /// Asked for, but Motion & Fitness isn't granted.
    case needsMotionAccess
    /// No motion coprocessor: no activity sample will ever be delivered.
    case unsupportedDevice
    /// Asked for, but there is no active subscription — recording new trips is
    /// what the subscription pays for, so nothing is watched.
    case needsSubscription
}

@Observable
final class DrivingDetector {
    private let motionActivityService: MotionActivityService
    private let tripRecorder: TripRecorder
    private let vehicleService: VehicleService
    private let notificationService: NotificationService
    private let locationService: LocationService
    private let modelContext: ModelContext

    private(set) var isEnabled: Bool

    /// Poussé depuis AppServices à chaque changement d'abonnement, plutôt que
    /// lu sur PurchaseService : la détection n'a pas à connaître StoreKit, elle
    /// a juste besoin de savoir si elle a le droit de tourner.
    private(set) var hasRecordingAccess: Bool

    /// What detection is really doing, as opposed to what the preference says.
    /// Read by the settings screen so the toggle can't claim to be on while
    /// nothing is watching. Cached rather than computed on demand so SwiftUI
    /// re-renders when it moves: two of its inputs are CoreMotion statics that
    /// no observation can see change.
    private(set) var status: DrivingDetectionStatus = .off

    /// Whether a just-finalized automatic trip still needs a yes/no answer
    /// (the notification + in-app review flow) or gets saved as `.confirmed`
    /// straight away. Plain settable property, unlike `isEnabled`: choosing
    /// this has no permissions to request, so the settings screen and the
    /// onboarding step can both bind to it directly.
    var requiresTripConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(requiresTripConfirmation, forKey: Self.requiresConfirmationKey)
        }
    }

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
    /// Falls back after a prompt with no reply, since declining the upgrade
    /// prompt (staying at "When In Use") doesn't always produce another
    /// authorization-change callback for escalateToAlwaysIfNeeded to react to.
    private var escalationTimeoutTask: Task<Void, Never>?
    private static let escalationTimeout: Duration = .seconds(10)

    /// How far back to look for a drive already under way when monitoring
    /// arms. Long enough to catch a trip that began before the app was woken,
    /// short enough that the reading still describes now.
    private static let recentActivityLookback: TimeInterval = 300

    private static let startValidationWindow: TimeInterval = 60
    private static let stopConfirmationWindow: TimeInterval = 300
    /// How long non-automotive activity must persist before a trip too short to
    /// be validated is thrown away. Without it, a red light 30 seconds after
    /// departure would discard a real trip that is only just starting.
    private static let discardGraceWindow: TimeInterval = 60
    private static let preferenceKey = "isAutoDetectionEnabled"
    private static let requiresConfirmationKey = "autoDetectionRequiresConfirmation"

    init(
        motionActivityService: MotionActivityService,
        tripRecorder: TripRecorder,
        vehicleService: VehicleService,
        notificationService: NotificationService,
        locationService: LocationService,
        modelContext: ModelContext,
        hasRecordingAccess: Bool
    ) {
        self.hasRecordingAccess = hasRecordingAccess
        self.motionActivityService = motionActivityService
        self.tripRecorder = tripRecorder
        self.vehicleService = vehicleService
        self.notificationService = notificationService
        self.locationService = locationService
        self.modelContext = modelContext
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        // Absent key means "never set" rather than "chose automatic": default
        // to true so upgrading users keep today's always-ask behavior instead
        // of being silently switched to auto-accept.
        self.requiresTripConfirmation = UserDefaults.standard.object(forKey: Self.requiresConfirmationKey) as? Bool ?? true

        // "Always" location can be granted or revoked from Settings while the
        // app isn't running, so monitoring is re-evaluated on every change
        // rather than trusting the status seen at launch.
        locationService.onAuthorizationChange = { [weak self] _ in
            self?.escalateToAlwaysIfNeeded()
            self?.refresh()
        }

        // Re-arms monitoring on every fresh process start — normal relaunch
        // after a force-quit, or a background relaunch triggered by a
        // significant location change — since isEnabled always starts false
        // in a brand new instance otherwise.
        refresh()
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.preferenceKey)
        isEscalatingToAlways = true
        lastEscalationRequestStatus = nil
        escalateToAlwaysIfNeeded()
        refresh()
    }

    /// Stops watching motion activity. A trip already in progress is left
    /// running — TripRecorder keeps recording it via the manual-mode path
    /// until finalized, rather than being cut off abruptly.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.preferenceKey)
        isEscalatingToAlways = false
        escalationTimeoutTask?.cancel()
        stopMonitoring()
        resetState()
        status = currentStatus
    }

    /// Ouvre ou ferme la détection selon l'abonnement. La *préférence* de
    /// l'utilisateur (`isEnabled`) n'est jamais touchée : reprendre son
    /// abonnement doit faire repartir la détection sans avoir à re-basculer un
    /// réglage qu'on aurait éteint dans son dos.
    func setRecordingAccess(_ hasAccess: Bool) {
        guard hasRecordingAccess != hasAccess else { return }
        hasRecordingAccess = hasAccess

        guard !hasAccess else {
            refresh()
            return
        }

        // L'abonnement tombe au milieu d'un trajet : le couper net donnerait
        // une distance fausse dans un rapport de frais, et arrêter la
        // surveillance tout de suite laisserait le trajet ouvert pour toujours,
        // GPS allumé, puisque plus rien ne viendrait constater sa fin. Le
        // trajet en cours va donc au bout ; c'est resetState(), à la
        // finalisation, qui coupera.
        guard !ownsTripInProgress else {
            status = currentStatus
            return
        }
        stopMonitoringForLostAccess()
    }

    private var ownsTripInProgress: Bool {
        recordingStartedAt != nil && tripRecorder.isRecording
    }

    private func stopMonitoringForLostAccess() {
        stopMonitoring()
        status = currentStatus
        AppLog.recording.notice("Auto-detection stopped: no active subscription.")
    }

    /// Waits until the "Always" escalation started by enable() has settled —
    /// granted, denied, or given up on after escalationTimeout with no
    /// reply. Onboarding awaits this so it only moves on once the user has
    /// actually answered every prompt, instead of racing ahead of them.
    func waitForAuthorizationSettled() async {
        while isEscalatingToAlways {
            try? await Task.sleep(for: .milliseconds(200))
        }
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
            armEscalationTimeout()
            // Calling requestAlwaysAuthorization() synchronously from inside
            // the very authorization-change callback that just reported the
            // previous grant is unreliable — CoreLocation can silently drop
            // it and never show the upgrade prompt. A short delay lets it
            // settle first.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.locationService.requestAlwaysAuthorization()
            }
        default:
            // Reached "Always", or the user declined outright — either way
            // there is nothing left to escalate toward.
            isEscalatingToAlways = false
            escalationTimeoutTask?.cancel()
        }
    }

    private func armEscalationTimeout() {
        escalationTimeoutTask?.cancel()
        escalationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.escalationTimeout)
            guard !Task.isCancelled else { return }
            self?.isEscalatingToAlways = false
        }
    }

    /// Recomputes `status` and arms monitoring if that has become possible.
    ///
    /// Must be called when the app returns to the foreground: Motion & Fitness
    /// can be granted from the Settings app, and CoreMotion reports that to
    /// nobody — without this, the user grants access, comes back, and finds a
    /// toggle still claiming to be blocked while nothing watches.
    func refresh() {
        status = currentStatus
        startMonitoringIfPossible()
    }

    private var currentStatus: DrivingDetectionStatus {
        guard isEnabled else { return .off }
        // Avant les permissions : c'est la cause la plus actionnable, et celle
        // qui explique vraiment pourquoi plus rien ne s'enregistre.
        guard hasRecordingAccess else { return .needsSubscription }
        guard motionActivityService.isAvailable else { return .unsupportedDevice }
        guard locationService.authorizationStatus == .authorizedAlways else { return .needsAlwaysLocation }
        guard motionActivityService.isAuthorized else { return .needsMotionAccess }
        return .running
    }

    /// Arms monitoring only when it can actually work — see `status`.
    private func startMonitoringIfPossible() {
        guard !isMonitoring else { return }

        switch status {
        case .off:
            return
        case .needsSubscription:
            AppLog.recording.notice("Auto-detection is on but there is no active subscription — monitoring stays off.")
            return
        case .unsupportedDevice:
            AppLog.recording.notice("Motion activity is unavailable on this device — auto-detection can't run.")
            return
        case .needsAlwaysLocation:
            AppLog.recording.notice("Auto-detection is on but \"Always\" location isn't granted — monitoring stays off.")
            return
        case .needsMotionAccess:
            // Never let arming monitoring be what asks for Motion & Fitness:
            // startActivityUpdates raises the prompt on its own, so a cold
            // start with the preference still on would show it straight away,
            // outside the onboarding step that is meant to introduce it.
            // Asking is done explicitly, and only there.
            AppLog.recording.notice("Motion & Fitness isn't granted — monitoring stays off rather than prompting from here.")
            return
        case .running:
            break
        }

        isMonitoring = true
        locationService.startSignificantLocationMonitoring()
        motionActivityService.startMonitoring { [weak self] activity in
            self?.handle(activity)
        }
        catchUpWithDrivingAlreadyUnderWay()
    }

    /// Core Motion delivers only changes from the moment monitoring arms, so a
    /// drive already in progress produces nothing until it ends. This is the
    /// path that catches it — most importantly when a significant location
    /// change has just relaunched the app mid-journey, which is exactly the
    /// case automatic detection exists to cover.
    private func catchUpWithDrivingAlreadyUnderWay() {
        Task { [weak self] in
            guard let self else { return }
            guard await motionActivityService.isAutomotiveNow(lookingBack: Self.recentActivityLookback) else { return }
            // Conditions can have changed while the query was in flight.
            guard isEnabled, isMonitoring, !tripRecorder.isRecording else { return }
            AppLog.recording.notice("Picking up a drive that was already under way when monitoring armed.")
            clearPendingDecision()
            startProvisionalTrip()
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
        // Le trajet qui était en cours quand l'abonnement est tombé vient de se
        // terminer : c'est ici, et pas avant, qu'on cesse de surveiller.
        if !hasRecordingAccess, isMonitoring {
            stopMonitoringForLostAccess()
        }
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
        // Un échantillon de mouvement peut arriver dans l'intervalle entre la
        // perte d'accès et l'arrêt effectif de la surveillance.
        guard hasRecordingAccess else { return }

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
            if requiresTripConfirmation {
                notificationService.scheduleTripConfirmationNotification(for: trip)
            } else {
                trip.confirmationStatus = .confirmed
                modelContext.saveOrLog()
            }
        }
        resetState()
    }
}
