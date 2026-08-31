//
//  ReportPeriodBoundary.swift
//  MyTrack
//
//  Pure calendar math for periodic reports: when the next report becomes due,
//  and which [start, end) trip window a due date covers. Kept separate from
//  ReportSettingsService so the boundary rules can be read/reasoned about on
//  their own.
//

import Foundation

enum ReportPeriodBoundary {
    /// Local hour at which a periodic report becomes due, so the notification
    /// and the launch-time check both land at a predictable time of day.
    static let dueHour = 9

    static func nextDueDate(
        after referenceDate: Date,
        periodicity: ReportPeriodicity,
        customIntervalDays: Int
    ) -> Date? {
        let calendar = Calendar.current
        switch periodicity {
        case .none:
            return nil
        case .weekly:
            return nextWeeklyDueDate(after: referenceDate, calendar: calendar)
        case .monthly:
            return nextAlignedDueDate(after: referenceDate, everyMonths: 1, calendar: calendar)
        case .quarterly:
            return nextAlignedDueDate(after: referenceDate, everyMonths: 3, calendar: calendar)
        case .yearly:
            return nextAlignedDueDate(after: referenceDate, everyMonths: 12, calendar: calendar)
        case .custom:
            let days = max(1, customIntervalDays)
            let base = calendar.date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
            return atDueHour(base, calendar: calendar)
        }
    }

    /// The [start, end) window a report generated for `dueDate` should cover.
    static func periodRange(
        endingAt dueDate: Date,
        periodicity: ReportPeriodicity,
        customIntervalDays: Int
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start: Date
        switch periodicity {
        case .none:
            start = dueDate
        case .weekly:
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: dueDate) ?? dueDate
        case .monthly:
            start = calendar.date(byAdding: .month, value: -1, to: dueDate) ?? dueDate
        case .quarterly:
            start = calendar.date(byAdding: .month, value: -3, to: dueDate) ?? dueDate
        case .yearly:
            start = calendar.date(byAdding: .month, value: -12, to: dueDate) ?? dueDate
        case .custom:
            start = calendar.date(byAdding: .day, value: -max(1, customIntervalDays), to: dueDate) ?? dueDate
        }
        return (start, dueDate)
    }

    /// Start of the week that follows `referenceDate`, pinned to `dueHour`.
    /// Aligned on the calendar's own first weekday — lundi ici, dimanche
    /// ailleurs — comme les mois le sont sur le 1er.
    private static func nextWeeklyDueDate(after referenceDate: Date, calendar: Calendar) -> Date {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start,
              let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)
        else { return referenceDate }
        return atDueHour(nextWeekStart, calendar: calendar)
    }

    /// Start of the next period aligned to January (so quarters land on
    /// Jan/Apr/Jul/Oct and years on Jan 1st) that begins strictly after
    /// `referenceDate`, pinned to `dueHour`.
    private static func nextAlignedDueDate(after referenceDate: Date, everyMonths: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let year = components.year, let month = components.month else { return referenceDate }
        let monthIndex0 = month - 1
        let alignedMonthIndex0 = (monthIndex0 / everyMonths) * everyMonths

        var nextComponents = DateComponents()
        nextComponents.year = year
        nextComponents.month = alignedMonthIndex0 + 1 + everyMonths
        nextComponents.day = 1
        let candidate = calendar.date(from: nextComponents) ?? referenceDate
        return atDueHour(candidate, calendar: calendar)
    }

    private static func atDueHour(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: dueHour, minute: 0, second: 0, of: date) ?? date
    }
}
