//
//  TripReportRow.swift
//  MyTrack
//
//  One line of a PDF report, snapshotted from a Trip while still on the main
//  actor. SwiftData models belong to the actor that owns their ModelContext
//  and can't be read from anywhere else, so the renderer works from these
//  plain values instead — which is precisely what lets the drawing itself run
//  off the main thread.
//
//  How the trip was recorded — auto-detected or entered by hand — is
//  deliberately absent: it's an implementation detail of the app, not of the
//  journey, and it told the report's reader nothing.
//

import Foundation

nonisolated struct TripReportRow: Sendable {
    let date: String
    let vehicleName: String
    let distance: String
    let duration: String
    /// Le prix de l'énergie retenu pour ce trajet — « 1,859 CHF/L » — et ce
    /// qu'il donne une fois la distance parcourue. « — » quand le véhicule du
    /// trajet n'a pas de quoi l'estimer.
    ///
    /// Le prix accompagne le coût plutôt que de le laisser tomber du ciel : sans
    /// lui, un lecteur ne peut pas refaire le calcul, et un rapport de frais qui
    /// ne se vérifie pas ne vaut pas grand-chose.
    let energyPrice: String
    let cost: String
    let distanceMeters: Double
    let durationSeconds: TimeInterval
    /// Le montant brut, pour le total du rapport. Nil, et non zéro, quand il n'y
    /// a pas de coût : un trajet dont on ne sait rien ne doit pas peser dans une
    /// somme comme s'il n'avait rien coûté.
    let costAmount: Double?
}

extension TripReportRow {
    init(trip: Trip, unit: DistanceUnit, locale: Locale) {
        self.init(
            date: trip.formattedStartDate(locale: locale),
            vehicleName: trip.vehicle?.name ?? "—",
            distance: trip.formattedDistance(in: unit, locale: locale),
            duration: trip.formattedDuration(locale: locale),
            energyPrice: trip.formattedEnergyPrice(locale: locale) ?? "—",
            cost: trip.formattedEnergyCost(locale: locale) ?? "—",
            distanceMeters: trip.distanceMeters,
            durationSeconds: (trip.endDate ?? .now).timeIntervalSince(trip.startDate),
            costAmount: trip.energyCost
        )
    }
}
