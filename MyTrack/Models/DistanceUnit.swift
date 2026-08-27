//
//  DistanceUnit.swift
//  MyTrack
//
//  Unit distances are displayed in. Deliberately not offering an "automatic"
//  case that follows the device region: the choice is explicit, and stays put
//  when the app language changes — un Français qui lit l'app en anglais ne veut
//  pas voir ses trajets basculer en miles.
//
//  `nonisolated` and `Sendable` because the value crosses into the detached
//  task that renders the PDF report, same reason as TripReportRow.
//

import SwiftUI

nonisolated enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case kilometers
    case miles

    var id: String { rawValue }

    /// `LocalizedStringKey` plutôt que `String` : la valeur est affichée telle
    /// quelle par SwiftUI, qui la résout avec la locale de l'environnement —
    /// celle de l'app, pas celle du système.
    var label: LocalizedStringKey {
        switch self {
        case .kilometers: return "Kilomètres"
        case .miles: return "Miles"
        }
    }

    /// L'unité que la région du système laisse attendre, pour que l'étape
    /// d'onboarding présente déjà la bonne : un iPhone réglé sur les
    /// États-Unis ou le Royaume-Uni compte ses trajets en miles. Ce n'est qu'un
    /// pré-choix — c'est l'utilisateur qui tranche, et son choix ne bouge plus.
    static var systemDefault: DistanceUnit {
        switch Locale.autoupdatingCurrent.measurementSystem {
        case .us, .uk: .miles
        default: .kilometers
        }
    }

    var unitLength: UnitLength {
        switch self {
        case .kilometers: return .kilometers
        case .miles: return .miles
        }
    }
}
