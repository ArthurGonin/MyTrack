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
            return .started
        }
    }

    func stopManualRecording() {
        tripRecorder.finalize(endDate: .now)
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
