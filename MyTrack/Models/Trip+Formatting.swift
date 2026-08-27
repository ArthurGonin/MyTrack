//
//  Trip+Formatting.swift
//  MyTrack
//

import Foundation

extension Trip {
    func formattedDistance(in unit: DistanceUnit, locale: Locale) -> String {
        TripFormatting.distance(meters: distanceMeters, unit: unit, locale: locale)
    }

    func formattedDuration(locale: Locale) -> String {
        TripFormatting.duration((endDate ?? Date()).timeIntervalSince(startDate), locale: locale)
    }

    func formattedStartDate(locale: Locale) -> String {
        TripFormatting.dateAndTime(startDate, locale: locale)
    }
}
