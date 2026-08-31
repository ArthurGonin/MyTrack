//
//  TripSortOrder.swift
//  MyTrack
//
//  L'ordre dans lequel la liste des trajets se range : quatre critères — la
//  date, le coût, la distance, la durée — pris chacun dans les deux sens.
//
//  Une seule valeur pour le critère et le sens, plutôt que deux réglages
//  séparés : c'est une seule chose à retenir, et le menu se lit d'un trait au
//  lieu de demander deux gestes pour dire « le plus cher d'abord ».
//
//  Valeur brute en `String` parce que le choix se garde d'un lancement à
//  l'autre (voir `TripListView`) : un nom écrit en toutes lettres survit à
//  l'ajout d'un critère au milieu de l'énumération, là où un rang numérique
//  décalerait tout ce qui est déjà rangé.
//

import SwiftUI

enum TripSortOrder: String, CaseIterable, Identifiable {
    /// Le plus récent d'abord : l'ordre par défaut, celui dans lequel la liste
    /// s'ouvrait avant qu'on puisse la trier.
    case dateDescending
    case dateAscending
    case costAscending
    case costDescending
    case distanceAscending
    case distanceDescending
    case durationAscending
    case durationDescending

    static let `default`: TripSortOrder = .dateDescending

    var id: String { rawValue }

    /// Une `LocalizedStringKey` et non une `String` : le menu la pose dans un
    /// `Text`, qui la résout avec la locale de l'environnement — celle de
    /// l'app, pas celle du système (même choix que `DistanceUnit`).
    ///
    /// Chaque libellé nomme son critère plutôt que de s'en remettre à un
    /// intitulé de section : « Croissant » seul ne dirait pas de quoi, et la
    /// même ligne se lirait à l'identique sous « Distance » et sous « Durée ».
    var label: LocalizedStringKey {
        switch self {
        case .dateDescending: "Plus récent d'abord"
        case .dateAscending: "Plus ancien d'abord"
        case .costAscending: "Coût croissant"
        case .costDescending: "Coût décroissant"
        case .distanceAscending: "Distance croissante"
        case .distanceDescending: "Distance décroissante"
        case .durationAscending: "Durée croissante"
        case .durationDescending: "Durée décroissante"
        }
    }
}
