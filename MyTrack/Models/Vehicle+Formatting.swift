//
//  Vehicle+Formatting.swift
//  MyTrack
//
//  Même partage des rôles que pour les trajets (voir `Trip+Formatting`) : le
//  modèle reste une entité, l'affichage vit dans une extension.
//
//  `locale` est passée plutôt que lue sur `Locale.current` : l'app a sa propre
//  langue, choisie à l'onboarding, qui n'est pas forcément celle du système.
//

import Foundation

extension Vehicle {
    /// « 6,5 L/100 km », ou nil si la consommation n'a pas été renseignée — il
    /// n'y a alors rien à afficher, et surtout rien à inventer.
    func formattedConsumption(locale: Locale) -> String? {
        guard let consumption, consumption > 0 else { return nil }
        return TripFormatting.energy(
            consumption, unitSymbol: energyType.consumptionUnitSymbol, locale: locale
        )
    }

    /// « 1,85 €/L », dans la devise de la région.
    ///
    /// Trois décimales autorisées, là où un coût de trajet s'arrête à deux : un
    /// carburant s'affiche au millième à la pompe (1,859 €/L), et deux décimales
    /// fixes arrondiraient à un prix que l'utilisateur n'a pas saisi.
    func formattedEnergyPrice(locale: Locale) -> String? {
        guard let energyPrice, energyPrice > 0 else { return nil }
        let amount = TripFormatting.currency(energyPrice, locale: locale, fractionLength: 2...3)
        return "\(amount)/\(energyType.energyUnitSymbol)"
    }
}
