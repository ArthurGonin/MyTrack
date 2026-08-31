//
//  VehicleDraft.swift
//  MyTrack
//
//  Ce qu'un formulaire de véhicule tient pendant la saisie. Les trois écrans
//  qui en éditent un — l'étape d'onboarding, l'ajout et la modification —
//  partagent ce brouillon plutôt qu'une poignée de `@State` chacun : un champ
//  qui s'ajoute s'ajoute alors une fois, et les trois écrans le reçoivent.
//
//  Les nombres y sont du texte et non des `Double` : un champ vide, un « 6, »
//  en cours de frappe ou une virgule là où l'app attendait un point sont des
//  états que traverse toute saisie, et qu'un `Double` ne sait pas représenter.
//  La conversion se fait au moment d'enregistrer, une bonne fois.
//

import Foundation

struct VehicleDraft {
    var name = ""
    var licensePlate = ""
    var energyType: VehicleEnergyType = .combustion
    var consumption = ""
    var energyPrice = ""

    init() {}

    /// Le brouillon d'un véhicule déjà enregistré, pour l'écran de
    /// modification. `locale` met les nombres en forme dans les conventions de
    /// l'app : un francophone retrouve « 6,5 » dans le champ, pas « 6.5 ».
    init(vehicle: Vehicle, locale: Locale) {
        name = vehicle.name
        licensePlate = vehicle.licensePlate ?? ""
        energyType = vehicle.energyType
        consumption = Self.text(from: vehicle.consumption, locale: locale)
        energyPrice = Self.text(from: vehicle.energyPrice, locale: locale)
    }

    /// Un véhicule a besoin d'un nom ; tout le reste est facultatif.
    var isValid: Bool { !trimmedName.isEmpty }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLicensePlate: String? {
        let trimmed = licensePlate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var consumptionValue: Double? { Self.number(from: consumption) }

    var energyPriceValue: Double? { Self.number(from: energyPrice) }

    /// Le véhicule que ce brouillon décrit, prêt à être inséré.
    func makeVehicle(isSelected: Bool = false) -> Vehicle {
        Vehicle(
            name: trimmedName,
            licensePlate: trimmedLicensePlate,
            isSelected: isSelected,
            energyType: energyType,
            consumption: consumptionValue,
            energyPrice: energyPriceValue
        )
    }

    /// Reporte le brouillon sur un véhicule déjà en base. À l'appelant
    /// d'enregistrer ensuite le contexte.
    func apply(to vehicle: Vehicle) {
        vehicle.name = trimmedName
        vehicle.licensePlate = trimmedLicensePlate
        vehicle.energyType = energyType
        vehicle.consumption = consumptionValue
        vehicle.energyPrice = energyPriceValue
    }

    private static func text(from value: Double?, locale: Locale) -> String {
        guard let value else { return "" }
        // Sans séparateur de milliers : ce qui est écrit dans le champ doit
        // pouvoir être relu tel quel, et une espace au milieu d'un nombre est
        // exactement ce qui casse une saisie au retour.
        return value.formatted(
            .number.precision(.fractionLength(0...3)).grouping(.never).locale(locale)
        )
    }

    /// Le nombre saisi, quelle que soit la façon dont il l'a été : le clavier
    /// décimal donne la virgule dans les langues qui s'en servent et le point
    /// ailleurs, et rien n'empêche un collage d'apporter l'autre. Zéro et les
    /// valeurs négatives valent « non renseigné » — une consommation nulle n'a
    /// pas de sens, et le champ est facultatif.
    private static func number(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace }
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
}
