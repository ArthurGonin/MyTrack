//
//  Trip+Formatting.swift
//  MyTrack
//

import Foundation

extension Trip {
    var formattedDistance: String {
        String(format: "%.1f km", distanceMeters / 1000)
    }

    var formattedDuration: String {
        let duration = (endDate ?? Date()).timeIntervalSince(startDate)
        let minutes = Int(duration / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }
}
