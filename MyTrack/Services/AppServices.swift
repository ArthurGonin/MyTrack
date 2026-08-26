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
    let userProfileService = UserProfileService()
    let reportProfileService = ReportProfileService()
    let locationService = LocationService()
    let motionActivityService = MotionActivityService()
    let reportGenerationService: ReportGenerationService
    let notificationService: NotificationService
    let tripRecorder: TripRecorder
    let drivingDetector: DrivingDetector

    init(modelContext: ModelContext) {
        reportGenerationService = ReportGenerationService(userProfileService: userProfileService)
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

    /// Wipes every trace of the user's data — trips, vehicles, generated report
    /// PDFs, profile and report settings — and stops background monitoring, so
    /// the app comes back looking like a fresh install. `UserProfile` and
    /// `ReportSettings` aren't recreated here: their services fetch-or-create
    /// on next access, so deleting the existing rows is enough.
    func eraseAllData(in context: ModelContext) {
        if tripRecorder.isRecording {
            tripRecorder.discard()
        }
        drivingDetector.disable()
        notificationService.cancelAllNotifications()

        if let reports = try? context.fetch(FetchDescriptor<GeneratedReport>()) {
            for report in reports {
                reportGenerationService.deleteReport(report, in: context)
            }
        }
        if let trips = try? context.fetch(FetchDescriptor<Trip>()) {
            for trip in trips {
                context.delete(trip)
            }
        }
        if let vehicles = try? context.fetch(FetchDescriptor<Vehicle>()) {
            for vehicle in vehicles {
                context.delete(vehicle)
            }
        }
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            for profile in profiles {
                context.delete(profile)
            }
        }
        if let profiles = try? context.fetch(FetchDescriptor<ReportProfile>()) {
            for profile in profiles {
                context.delete(profile)
            }
        }

        try? context.save()
    }
}
