//
//  DistanceUnit.swift
//  MyTrack
//
//  Unit distances are displayed in. Deliberately not offering an "automatic"
//  case that follows the device region: the app ships in French only, so the
//  automatic and kilometres choices would always resolve to the same thing.
//  Adding `.automatic` later — if the app gets localized — only means one more
//  case here and one more branch in TripFormatting.
//
//  `nonisolated` and `Sendable` because the value crosses into the detached
//  task that renders the PDF report, same reason as TripReportRow.
//

import Foundation

nonisolated enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case kilometers
    case miles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kilometers: return "Kilomètres"
        case .miles: return "Miles"
        }
    }

    var unitLength: UnitLength {
        switch self {
        case .kilometers: return .kilometers
        case .miles: return .miles
        }
    }
}
