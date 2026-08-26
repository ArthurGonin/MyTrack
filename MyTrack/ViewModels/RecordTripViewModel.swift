//
//  RecordTripViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData
import CoreLocation

struct RecordTripViewModel {
    let tripRecorder: TripRecorder
    let locationService: LocationService
    let vehicleService: VehicleService
    let drivingDetector: DrivingDetector
    let notificationService: NotificationService

    var isRecording: Bool { tripRecorder.isRecording }
    var currentDistanceMeters: Double { tripRecorder.currentDistanceMeters }
    var currentStartDate: Date? { tripRecorder.currentStartDate }
    var isAutoDetectionEnabled: Bool { drivingDetector.isEnabled }

    enum StartResult {
        case started
        case permissionRequested
        case permissionDenied
    }

    func startManualRecording(in context: ModelContext) -> StartResult {
        switch locationService.authorizationStatus {
        case .notDetermined:
            locationService.requestWhenInUseAuthorization()
            return .permissionRequested
        case .denied, .restricted:
            return .permissionDenied
        default:
            let vehicle = vehicleService.selectedVehicle(in: context)
            tripRecorder.start(vehicle: vehicle, source: .manual)
            // Recording refuses to start if authorization was revoked between
            // the check above and now, leaving nothing recorded — surface that
            // as a denial rather than showing a trip that isn't running.
            return tripRecorder.isRecording ? .started : .permissionDenied
        }
    }

    /// Ends the recording in progress, whichever mode started it.
    ///
    /// Stopping a trip by hand from inside the app is itself the confirmation:
    /// the user plainly knows this trip exists, so asking again would only hide
    /// it from the trip list — which shows confirmed trips only — until they
    /// answered a notification that this path never sends.
    func stopManualRecording(in context: ModelContext) {
        // An automatically detected trip that has already stopped moving ends
        // where the driving ended, not now.
        let endDate = drivingDetector.ownedTripDrivingStoppedAt ?? .now
        guard let trip = tripRecorder.finalize(endDate: endDate) else { return }

        trip.confirmationStatus = .confirmed
        context.saveOrLog()
        drivingDetector.forgetOwnedTrip()
    }

    enum AutoDetectionEnableResult {
        case enabled
        case permissionRequested
        case permissionDenied
    }

    /// Requests the "Always" location upgrade + notifications permission the
    /// moment auto-detection is turned on, rather than during onboarding.
    /// If permission isn't already granted, the user needs to flip the
    /// toggle again after responding to the system prompt.
    func enableAutoDetection() -> AutoDetectionEnableResult {
        switch locationService.authorizationStatus {
        case .authorizedAlways:
            notificationService.requestAuthorization()
            drivingDetector.enable()
            return .enabled
        case .denied, .restricted:
            return .permissionDenied
        default:
            locationService.requestAlwaysAuthorization()
            notificationService.requestAuthorization()
            return .permissionRequested
        }
    }

    func disableAutoDetection() {
        drivingDetector.disable()
    }

    /// Changes which vehicle the *next* recording (manual or automatic) will
    /// be attributed to. Does not affect trips already recorded.
    func selectVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.select(vehicle, in: context)
    }
}
