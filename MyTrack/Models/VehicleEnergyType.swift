//
//  VehicleEnergyType.swift
//  MyTrack
//
//  L'énergie d'un véhicule, et ce qui en découle : l'unité dans laquelle se
//  compte sa consommation — des litres pour ce qui brûle, des kilowattheures
//  pour ce qui se recharge — et celle dans laquelle se paie son plein.
//
//  L'hybride est rangé du côté du carburant : c'est en litres aux 100 km que sa
//  consommation s'annonce, et l'électricité qu'il récupère au freinage ne
//  s'achète pas.
//
//  Le libellé est rendu en `String` plutôt qu'en `LocalizedStringKey` : il
//  s'affiche tel quel dans les `Picker`, mais il se recolle aussi à d'autres
//  morceaux dans le résumé d'une ligne de la liste des véhicules, ce qu'une clé
//  ne permet pas. Une seule définition pour les deux, plutôt que deux qui
//  finiraient par diverger.
//

import Foundation

enum VehicleEnergyType: String, Codable, CaseIterable, Identifiable {
    case combustion
    case electric
    case hybrid

    var id: String { rawValue }

    func label(bundle: Bundle, locale: Locale) -> String {
        switch self {
        case .combustion: String(localized: "Thermique", bundle: bundle, locale: locale)
        case .electric: String(localized: "Électrique", bundle: bundle, locale: locale)
        case .hybrid: String(localized: "Hybride", bundle: bundle, locale: locale)
        }
    }

    var symbolName: String {
        switch self {
        case .combustion: "fuelpump"
        case .electric: "bolt"
        case .hybrid: "bolt.car"
        }
    }

    /// L'unité de la consommation, « 6,5 L/100 km » ou « 16 kWh/100 km ».
    ///
    /// Pas traduite : c'est une notation technique, qui s'écrit de la même
    /// façon d'une langue à l'autre. Toujours aux 100 km, y compris pour qui
    /// lit ses distances en miles — c'est la consommation telle qu'elle est
    /// inscrite sur la carte grise et sur les bornes, et la convertir en donnant
    /// une valeur que l'utilisateur ne pourrait recopier de nulle part.
    var consumptionUnitSymbol: String {
        switch self {
        case .combustion, .hybrid: "L/100 km"
        case .electric: "kWh/100 km"
        }
    }

    /// Ce qui s'achète, et dont on saisit donc le prix unitaire — le litre ou
    /// le kilowattheure.
    var energyUnitSymbol: String {
        switch self {
        case .combustion, .hybrid: "L"
        case .electric: "kWh"
        }
    }
}
