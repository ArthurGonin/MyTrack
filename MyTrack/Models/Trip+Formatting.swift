//
//  Trip+Formatting.swift
//  MyTrack
//

import Foundation

extension Trip {
    func formattedDistance(in unit: DistanceUnit) -> String {
        TripFormatting.distance(meters: distanceMeters, unit: unit)
    }

    var formattedDuration: String {
        TripFormatting.duration((endDate ?? Date()).timeIntervalSince(startDate))
    }

    var formattedStartDate: String {
        startDate.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedSource: String {
        source == .automatic ? "Automatique" : "Manuel"
    }
}
