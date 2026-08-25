//
//  TripRecorder.swift
//  MyTrack
//
//  Shared recording engine: the only component that starts/stops active
//  GPS tracking. Both manual mode (RecordTripViewModel) and automatic mode
//  (DrivingDetector) drive this instead of touching CLLocationManager
//  themselves, so there is a single place where a trip is actually recorded.
//

import Foundation
import CoreLocation
import SwiftData
import Observation

@Observable
final class TripRecorder {
    private let locationService: LocationService
    private let modelContext: ModelContext

    private(set) var isRecording = false
    private(set) var currentDistanceMeters: Double = 0
    private(set) var currentStartDate: Date?

    private var activeTrip: Trip?
    private var lastAcceptedLocation: CLLocation?
    private var pointsSinceLastCheckpoint = 0

    private static let checkpointInterval = 10
    private static let maxPlausibleSpeed: CLLocationSpeed = 60 // m/s (~216 km/h) — rejects GPS glitches

    init(locationService: LocationService, modelContext: ModelContext) {
        self.locationService = locationService
        self.modelContext = modelContext
    }

    /// Finds any trip left with `endDate == nil` by a previous process that
    /// died mid-recording (crash, or the system killing a backgrounded app)
    /// and closes it out instead of leaving it stuck "in progress" forever.
    /// An automatic trip that never reached the 60s validation mark is
    /// discarded, matching what DrivingDetector would have done live; anything
    /// else (manual, or automatic past 60s) is finalized at its last known point.
    func cleanUpOrphanedTrips() {
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil })
        guard let orphans = try? modelContext.fetch(descriptor) else { return }

        for trip in orphans {
            guard let lastPoint = trip.routePoints.last else {
                modelContext.delete(trip)
                continue
            }

            let recordedDuration = lastPoint.timestamp.timeIntervalSince(trip.startDate)
            if trip.source == .automatic && recordedDuration < 60 {
                modelContext.delete(trip)
            } else {
                trip.endDate = lastPoint.timestamp
                trip.endLatitude = lastPoint.latitude
                trip.endLongitude = lastPoint.longitude
            }
        }
        try? modelContext.save()
    }

    func start(vehicle: Vehicle?, source: TripSource) {
        guard !isRecording else { return }

        let trip = Trip(startDate: .now, source: source, vehicle: vehicle)
        modelContext.insert(trip)
        try? modelContext.save()

        activeTrip = trip
        lastAcceptedLocation = nil
        pointsSinceLastCheckpoint = 0
        currentDistanceMeters = 0
        currentStartDate = trip.startDate
        isRecording = true

        locationService.onLocationUpdate = { [weak self] location in
            self?.handle(location)
        }
        locationService.startActiveTracking()
    }

    /// Stops tracking and deletes the in-progress trip entirely — used when
    /// DrivingDetector decides an automatic trip was too short to be real.
    func discard() {
        guard let trip = activeTrip else { return }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil
        modelContext.delete(trip)
        try? modelContext.save()
        resetState()
    }

    /// Ends the trip normally and saves it. Source-agnostic: manual mode calls
    /// this directly with `.now`; DrivingDetector calls it with the moment
    /// driving actually stopped (not when the stop-confirmation window ends).
    /// Returns the finalized trip so DrivingDetector can schedule a
    /// confirmation notification for it.
    @discardableResult
    func finalize(endDate: Date) -> Trip? {
        guard let trip = activeTrip else { return nil }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil

        trip.endDate = endDate
        if let last = lastAcceptedLocation {
            trip.endLatitude = last.coordinate.latitude
            trip.endLongitude = last.coordinate.longitude
        }
        trip.distanceMeters = currentDistanceMeters
        try? modelContext.save()

        resetState()
        return trip
    }

    private func resetState() {
        activeTrip = nil
        lastAcceptedLocation = nil
        pointsSinceLastCheckpoint = 0
        currentDistanceMeters = 0
        currentStartDate = nil
        isRecording = false
    }

    private func handle(_ location: CLLocation) {
        guard let trip = activeTrip else { return }

        if let last = lastAcceptedLocation {
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            if elapsed > 0, last.distance(from: location) / elapsed > Self.maxPlausibleSpeed {
                return
            }
        }

        if trip.startLatitude == nil {
            trip.startLatitude = location.coordinate.latitude
            trip.startLongitude = location.coordinate.longitude
        }

        if let last = lastAcceptedLocation {
            currentDistanceMeters += last.distance(from: location)
        }

        trip.routePoints.append(
            RoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp
            )
        )
        trip.distanceMeters = currentDistanceMeters
        lastAcceptedLocation = location

        pointsSinceLastCheckpoint += 1
        if pointsSinceLastCheckpoint >= Self.checkpointInterval {
            pointsSinceLastCheckpoint = 0
            try? modelContext.save()
        }
    }
}
