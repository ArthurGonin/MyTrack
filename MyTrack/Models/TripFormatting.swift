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
    /// separator follow the reader's locale ("12,3 km" in French, "7.6 mi" in
    /// English). A negative distance is clamped to zero — distance never
    /// legitimately goes backwards, so a corrupted value shows as "0 km"
    /// rather than "-12,3 km".
    static func distance(meters: Double, unit: DistanceUnit, fractionDigits: Int = 1) -> String {
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
            )
    }

    /// "45 min" under an hour, "1h05" past it. Clamped to zero for the same
    /// reason as `distance(meters:fractionDigits:)`: an end date earlier than
    /// its start date would otherwise render as "-5 min".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        guard minutes >= 60 else { return "\(minutes) min" }
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }
}
