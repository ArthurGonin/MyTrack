//
//  ReportSettingsService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class ReportSettingsService {
    /// The app has a single local report-settings record — fetches it, creating one on first access.
    func currentSettings(in context: ModelContext) -> ReportSettings {
        let descriptor = FetchDescriptor<ReportSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = ReportSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    /// Switches the active periodicity. For `.custom`, the interval and the next due date
    /// are chosen separately by the user (see `updateCustomInterval` and
    /// `updateCustomNextDueDate`), so this only seeds a default next due date the first
    /// time `.custom` is selected — it never overwrites a date the user already picked.
    @discardableResult
    func updatePeriodicity(_ periodicity: ReportPeriodicity, in context: ModelContext) -> ReportSettings {
        let settings = currentSettings(in: context)
        let periodicityChanged = settings.periodicity != periodicity
        settings.periodicity = periodicity
        if periodicity != .custom || periodicityChanged {
            settings.nextDueDate = ReportPeriodBoundary.nextDueDate(
                after: .now,
                periodicity: periodicity,
                customIntervalDays: settings.customIntervalDays
            )
        }
        try? context.save()
        return settings
    }

    /// Sets how often a custom-schedule report repeats, without touching the next due
    /// date the user picked.
    @discardableResult
    func updateCustomInterval(days: Int, in context: ModelContext) -> ReportSettings {
        let settings = currentSettings(in: context)
        settings.periodicity = .custom
        settings.customIntervalDays = max(1, days)
        try? context.save()
        return settings
    }

    /// Sets the exact date/time of the next custom-schedule report, as chosen by the user.
    @discardableResult
    func updateCustomNextDueDate(_ date: Date, in context: ModelContext) -> ReportSettings {
        let settings = currentSettings(in: context)
        settings.periodicity = .custom
        settings.nextDueDate = date
        try? context.save()
        return settings
    }

    /// Returns the trip window to generate a report for, if a periodic report is due, `nil` otherwise.
    func periodDueForGeneration(settings: ReportSettings, now: Date) -> (periodStart: Date, periodEnd: Date)? {
        guard settings.periodicity != .none, let nextDueDate = settings.nextDueDate, now >= nextDueDate else {
            return nil
        }
        let range = ReportPeriodBoundary.periodRange(
            endingAt: nextDueDate,
            periodicity: settings.periodicity,
            customIntervalDays: settings.customIntervalDays
        )
        return (range.start, range.end)
    }

    /// Call after a periodic report was successfully generated through `periodEnd`.
    /// Returns the new due date so the caller can reschedule the "report ready" notification.
    @discardableResult
    func advanceAfterGeneration(settings: ReportSettings, generatedThrough periodEnd: Date, in context: ModelContext) -> Date? {
        settings.lastGeneratedAt = periodEnd
        settings.nextDueDate = ReportPeriodBoundary.nextDueDate(
            after: periodEnd,
            periodicity: settings.periodicity,
            customIntervalDays: settings.customIntervalDays
        )
        try? context.save()
        return settings.nextDueDate
    }
}
