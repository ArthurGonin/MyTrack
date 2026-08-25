//
//  AppServices.swift
//  MyTrack
//
//  Composition root: holds one shared instance of each service, injected
//  into the SwiftUI environment from MyTrackApp. Built with the app's single
//  ModelContext so writes made outside the view hierarchy (e.g. by
//  TripRecorder or DrivingDetector while the app is backgrounded) are
//  visible to @Query views.
//

import Foundation
import SwiftData
import Observation

@Observable
final class AppServices {
    let vehicleService = VehicleService()
    let locationService = LocationService()
    let motionActivityService = MotionActivityService()
    let notificationService: NotificationService
    let tripRecorder: TripRecorder
    let drivingDetector: DrivingDetector

    init(modelContext: ModelContext) {
        notificationService = NotificationService(modelContext: modelContext)
        tripRecorder = TripRecorder(locationService: locationService, modelContext: modelContext)
        drivingDetector = DrivingDetector(
            motionActivityService: motionActivityService,
            tripRecorder: tripRecorder,
            vehicleService: vehicleService,
            notificationService: notificationService,
            locationService: locationService,
            modelContext: modelContext
        )

        tripRecorder.cleanUpOrphanedTrips()
    }
}
