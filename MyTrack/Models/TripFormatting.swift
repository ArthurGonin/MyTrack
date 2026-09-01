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

    /// La même distance, mais en deux morceaux : le nombre d'un côté, le
    /// symbole de l'unité de l'autre.
    ///
    /// Le compteur de l'écran d'accueil écrit les deux dans des tailles
    /// différentes — un grand nombre, un petit « km » posé à côté — ce qu'une
    /// chaîne d'un seul tenant ne permet pas. Le nombre passe malgré tout par
    /// le formateur de Foundation, pour que le séparateur de milliers suive la
    /// langue de l'app (« 12 345 » en français, « 12,345 » en anglais).
    static func distanceParts(
        meters: Double, unit: DistanceUnit, locale: Locale, fractionDigits: Int = 0
    ) -> (value: String, symbol: String) {
        let measurement = Measurement(value: max(0, meters), unit: UnitLength.meters)
            .converted(to: unit.unitLength)
        let value = measurement.value.formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale)
        )
        return (value, measurement.unit.symbol)
    }

    /// Un montant dans la devise de la région : « 1,51 CHF », « 12,40 € ».
    ///
    /// La devise vient de la région de l'appareil et non de la langue de l'app —
    /// un Suisse qui lit l'app en anglais paie toujours en francs. Sans région
    /// connue, le montant s'écrit nu plutôt qu'avec un symbole deviné.
    ///
    /// Deux décimales comme un ticket de caisse ; le prix d'un litre en demande
    /// une troisième (1,859 €/L), d'où le paramètre.
    static func currency(
        _ amount: Double, locale: Locale, fractionLength: ClosedRange<Int> = 2...2
    ) -> String {
        guard let currencyCode = locale.currency?.identifier else {
            return amount.formatted(.number.precision(.fractionLength(fractionLength)).locale(locale))
        }
        return amount.formatted(
            .currency(code: currencyCode).precision(.fractionLength(fractionLength)).locale(locale)
        )
    }

    /// « 0,81 L », « 12,4 kWh », « 6,5 L/100 km » : le nombre suit la langue de
    /// l'app, le symbole est une notation technique qui ne se traduit pas.
    static func energy(_ amount: Double, unitSymbol: String, locale: Locale) -> String {
        let value = amount.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return "\(value) \(unitSymbol)"
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

    /// « 18:40 » — la même durée, dite comme une horloge.
    ///
    /// Réservée aux tuiles de l'accueil. `duration` y donnerait « 18h 40min »
    /// en français et « 18 Std. 40 Min. » en allemand, qui ne tiennent pas à la
    /// taille où le chiffre doit se lire : la tuile le rapetisserait jusqu'à
    /// lui faire perdre ce qu'on est venu chercher. Ce format-là s'écrit pareil
    /// dans les six langues, et c'est justement ce qui le rend court.
    ///
    /// Il ne se lit que sous son intitulé — « temps de conduite » — sans quoi
    /// on croirait à une heure de la journée.
    static func clockDuration(_ interval: TimeInterval, locale: Locale) -> String {
        Duration.seconds(max(0, interval))
            .formatted(.time(pattern: .hourMinute).locale(locale))
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
