//
//  TripFormatting.swift
//  MyTrack
//
//  Distance and duration display formatting, shared by the trip screens and
//  the PDF report so a trip always reads the same way in both. Kept out of
//  Trip itself because reports also format aggregates (a period total) that
//  belong to no single trip.
//

import Foundation

nonisolated enum TripFormatting {
    /// The distance in the unit the user picked in Settings, formatted through
    /// Foundation's Measurement API so both the symbol and the decimal
    /// separator follow `locale` ("12,3 km" in French, "7.6 mi" in English). A
    /// negative distance is clamped to zero — distance never legitimately goes
    /// backwards, so a corrupted value shows as "0 km" rather than "-12,3 km".
    ///
    /// `locale` is passed in rather than left to `Locale.current`: the app has
    /// its own language, chosen at onboarding, which is not necessarily the
    /// one the system is set to.
    static func distance(
        meters: Double, unit: DistanceUnit, locale: Locale, fractionDigits: Int = 1
    ) -> String {
        Measurement(value: max(0, meters), unit: UnitLength.meters)
            .converted(to: unit.unitLength)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    // Required: without it `usage` defaults to `.general`, which
                    // re-picks the unit from the locale and the magnitude — it
                    // would print km for a reader in France whatever the user
                    // chose, and turn a 0 m trip into "0 cm".
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
                )
                .locale(locale)
            )
    }

    /// « 45min », « 1h 5min » — la mise en forme vient de Foundation plutôt que
    /// d'un `String(format: "%dh%02d")` maison, parce que chaque langue abrège
    /// ses unités à sa façon (« 1 Std. 5 Min. » en allemand). `narrow` plutôt
    /// qu'`abbreviated` : celui-ci intercale une conjonction (« 1 h et 5 min »)
    /// trop longue pour une colonne de tableau. Ramené à zéro pour la même
    /// raison que `distance` : une date de fin antérieure à son début se
    /// lirait sinon « -5 min ».
    static func duration(_ interval: TimeInterval, locale: Locale) -> String {
        Duration.seconds(max(0, interval))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow).locale(locale))
    }

    /// Les trois formats de date de l'app, regroupés ici pour la même raison
    /// que le reste : `Date.formatted` suit `Locale.current`, donc la langue du
    /// système, et pas celle que l'utilisateur a choisie dans l'app.
    static func dateAndTime(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    static func shortDate(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }

    static func longDate(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
    }
}
