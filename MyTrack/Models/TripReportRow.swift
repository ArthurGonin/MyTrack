//
//  TripReportRow.swift
//  MyTrack
//
//  One line of a PDF report, snapshotted from a Trip while still on the main
//  actor. SwiftData models belong to the actor that owns their ModelContext
//  and can't be read from anywhere else, so the renderer works from these
//  plain values instead — which is precisely what lets the drawing itself run
//  off the main thread.
//

import Foundation

nonisolated struct TripReportRow: Sendable {
    let date: String
    let vehicleName: String
    let distance: String
    let duration: String
    let source: String
    let distanceMeters: Double
    let durationSeconds: TimeInterval
}

extension TripReportRow {
    init(trip: Trip, unit: DistanceUnit) {
        self.init(
            date: trip.formattedStartDate,
            vehicleName: trip.vehicle?.name ?? "—",
            distance: trip.formattedDistance(in: unit),
            duration: trip.formattedDuration,
            source: trip.formattedSource,
            distanceMeters: trip.distanceMeters,
            durationSeconds: (trip.endDate ?? .now).timeIntervalSince(trip.startDate)
        )
    }
}
