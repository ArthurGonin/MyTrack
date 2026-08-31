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

    /// « 6,5 L/100 km » — la consommation retenue pour ce trajet.
    ///
    /// Celle du trajet et non celle du véhicule : c'est elle qui a servi au
    /// calcul, et elle seule explique le coût affiché juste en dessous.
    func formattedConsumption(locale: Locale) -> String? {
        guard let figures = energyFigures, figures.consumption > 0 else { return nil }
        return TripFormatting.energy(
            figures.consumption,
            unitSymbol: figures.energyType.consumptionUnitSymbol,
            locale: locale
        )
    }

    /// « 1,859 CHF/L » — le prix de l'énergie retenu pour ce trajet.
    func formattedEnergyPrice(locale: Locale) -> String? {
        guard let figures = energyFigures, let price = figures.price, price > 0 else { return nil }
        let amount = TripFormatting.currency(price, locale: locale, fractionLength: 2...3)
        return "\(amount)/\(figures.energyType.energyUnitSymbol)"
    }

    /// « 0,81 L » — l'énergie dépensée sur le trajet, ou nil quand elle ne peut
    /// pas être estimée (voir `Trip+Cost`).
    func formattedEnergyUsed(locale: Locale) -> String? {
        guard let energyUsed, let figures = energyFigures else { return nil }
        return TripFormatting.energy(
            energyUsed, unitSymbol: figures.energyType.energyUnitSymbol, locale: locale
        )
    }

    /// « 1,51 CHF » — ce que le trajet a coûté en énergie.
    func formattedEnergyCost(locale: Locale) -> String? {
        guard let energyCost else { return nil }
        return TripFormatting.currency(energyCost, locale: locale)
    }
}
