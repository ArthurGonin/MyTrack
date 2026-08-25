//
//  DrivingDetector.swift
//  MyTrack
//
//  State machine that turns raw Core Motion activity samples into
//  start/discard/stop decisions for an automatic trip, driving the shared
//  TripRecorder. GPS starts the instant automotive activity is first seen;
//  if it doesn't last 60s the trip is discarded as noise. Past that point,
//  ending requires 5 minutes of continuous non-automotive activity, and GPS
//  keeps running through that window so the route isn't cut if driving
//  resumes (traffic light, ferry, etc).
//

import Foundation
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

    private var recordingStartedAt: Date?
    private var isValidated = false
    private var stopCandidateSince: Date?

    private static let startValidationWindow: TimeInterval = 60
    private static let stopConfirmationWindow: TimeInterval = 300
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

        // Re-arms monitoring on every fresh process start — normal relaunch
        // after a force-quit, or a background relaunch triggered by a
        // significant location change — since isEnabled always starts false
        // in a brand new instance otherwise.
        if isEnabled {
            startMonitoring()
        }
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.preferenceKey)
        startMonitoring()
    }

    /// Stops watching motion activity. A trip already in progress is left
    /// running — TripRecorder keeps recording it via the manual-mode path
    /// until finalized, rather than being cut off abruptly.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.preferenceKey)
        locationService.stopSignificantLocationMonitoring()
        motionActivityService.stopMonitoring()
        resetState()
    }

    private func startMonitoring() {
        locationService.startSignificantLocationMonitoring()
        motionActivityService.startMonitoring { [weak self] activity in
            self?.handle(activity)
        }
    }

    private func resetState() {
        recordingStartedAt = nil
        isValidated = false
        stopCandidateSince = nil
    }

    private func handle(_ activity: CMMotionActivity) {
        guard activity.confidence != .low else { return }

        if activity.automotive {
            stopCandidateSince = nil

            if !tripRecorder.isRecording {
                startProvisionalTrip()
            } else if !isValidated,
                      let startedAt = recordingStartedAt,
                      Date().timeIntervalSince(startedAt) >= Self.startValidationWindow {
                isValidated = true
            }
            return
        }

        guard tripRecorder.isRecording else { return }

        guard isValidated else {
            tripRecorder.discard()
            resetState()
            return
        }

        let candidateStart = stopCandidateSince ?? Date()
        stopCandidateSince = candidateStart

        if Date().timeIntervalSince(candidateStart) >= Self.stopConfirmationWindow {
            finalizeTrip(endDate: candidateStart)
        }
    }

    private func startProvisionalTrip() {
        let vehicle = vehicleService.selectedVehicle(in: modelContext)
        tripRecorder.start(vehicle: vehicle, source: .automatic)
        recordingStartedAt = Date()
        isValidated = false
        stopCandidateSince = nil
    }

    private func finalizeTrip(endDate: Date) {
        if let trip = tripRecorder.finalize(endDate: endDate) {
            notificationService.scheduleTripConfirmationNotification(for: trip)
        }
        resetState()
    }
}
