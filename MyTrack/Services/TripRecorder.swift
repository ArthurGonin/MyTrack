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

    /// Whether the trip in progress has at least one accepted GPS point.
    /// A trip that has none would be saved as an empty 0 km route.
    var hasRecordedRoutePoints: Bool { lastAcceptedLocation != nil }

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
        modelContext.saveOrLog()
    }

    /// Starts recording, unless location isn't authorized — in which case no
    /// Trip row is created at all, rather than leaving an empty one behind that
    /// could never receive a single point. Callers check `isRecording` to know.
    func start(vehicle: Vehicle?, source: TripSource) {
        guard !isRecording else { return }

        locationService.onLocationUpdate = { [weak self] location in
            self?.handle(location)
        }
        guard locationService.startActiveTracking() else {
            locationService.onLocationUpdate = nil
            return
        }

        let trip = Trip(startDate: .now, source: source, vehicle: vehicle)
        modelContext.insert(trip)
        modelContext.saveOrLog()

        activeTrip = trip
        lastAcceptedLocation = nil
        pointsSinceLastCheckpoint = 0
        currentDistanceMeters = 0
        currentStartDate = trip.startDate
        isRecording = true
    }

    /// Stops tracking and deletes the in-progress trip entirely — used when
    /// DrivingDetector decides an automatic trip was too short to be real.
    func discard() {
        guard let trip = activeTrip else { return }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil
        modelContext.delete(trip)
        modelContext.saveOrLog()
        resetState()
    }

    /// Ends the trip normally and saves it. Source-agnostic: manual mode calls
    /// this directly with `.now`; DrivingDetector calls it with the moment
    /// driving actually stopped (not when the stop-confirmation window ends).
    /// Returns the finalized trip so DrivingDetector can schedule a
    /// confirmation notification for it.
    ///
    /// La trace est ramenée à la fenêtre du trajet, et la distance recalculée
    /// dessus. C'est tout l'écart entre les deux appelants : le mode manuel
    /// termine à `.now`, donc rien n'est retiré, tandis que la détection
    /// automatique termine au moment où la conduite s'est arrêtée — cinq minutes
    /// avant, le temps de la fenêtre de confirmation d'arrêt, pendant laquelle
    /// le GPS tournait encore. Les points de ces cinq minutes-là étaient comptés
    /// dans la distance sans l'être dans la durée : trois cents mètres à pied
    /// entre la voiture et le bureau s'ajoutaient à chaque trajet, et un rapport
    /// de frais kilométriques les facturait.
    @discardableResult
    func finalize(endDate: Date) -> Trip? {
        guard let trip = activeTrip else { return nil }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil

        let recorded = trip.routePoints.filter { $0.timestamp <= endDate }

        // Rien avant la fin de la conduite : le GPS n'avait rien accroché de la
        // course elle-même. Il n'y a ni trace ni distance à garder, et un trajet
        // de zéro kilomètre n'a rien à faire dans une liste — même raison que la
        // garde de `DrivingDetector.finalizeTrip`.
        guard let last = recorded.last else {
            modelContext.delete(trip)
            modelContext.saveOrLog()
            resetState()
            return nil
        }

        trip.endDate = endDate
        trip.routePoints = recorded
        trip.distanceMeters = Self.distance(over: recorded)
        trip.endLatitude = last.latitude
        trip.endLongitude = last.longitude
        modelContext.saveOrLog()

        resetState()
        return trip
    }

    /// La longueur d'une trace, point à point.
    ///
    /// Le même calcul que celui qu'accumule `handle(_:)` — `CLLocation.distance`
    /// sur des points consécutifs — donc le même résultat quand rien n'est
    /// retiré : la distance enregistrée ne saute pas par rapport à celle qui
    /// s'affichait pendant la course.
    private static func distance(over points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            let from = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let to = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + from.distance(from: to)
        }
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
            // A point that isn't strictly newer than the last accepted one is a
            // duplicate or an out-of-order delivery: it can't be speed-checked,
            // so it's dropped rather than let through unchecked.
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            guard elapsed > 0 else { return }
            guard last.distance(from: location) / elapsed <= Self.maxPlausibleSpeed else { return }
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
            modelContext.saveOrLog()
        }
    }
}
