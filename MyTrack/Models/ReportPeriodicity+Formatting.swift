//
//  ReportPeriodicity+Formatting.swift
//  MyTrack
//
//  Même partage des rôles que pour les trajets (voir `Trip+Formatting`) :
//  l'enum reste une valeur, son libellé vit dans une extension.
//
//  Une `LocalizedStringKey` et non une `String` : les trois écrans qui
//  l'affichent la posent dans un `Text`, qui la résout avec la locale de
//  l'environnement. Là où il faut une chaîne construite hors SwiftUI — le
//  sous-titre de `ReportSettingsView`, qui replie aussi `.custom` en
//  « Tous les N jours » — c'est `String(localized:bundle:locale:)` qui s'en
//  charge sur place.
//

import SwiftUI

extension ReportPeriodicity {
    var label: LocalizedStringKey {
        switch self {
        case .none: "Désactivé"
        case .weekly: "Hebdomadaire"
        case .monthly: "Mensuel"
        case .quarterly: "Trimestriel"
        case .yearly: "Annuel"
        case .custom: "Personnalisé"
        }
    }
}
