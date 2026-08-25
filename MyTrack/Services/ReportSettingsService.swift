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

    @discardableResult
    func updatePeriodicity(
        _ periodicity: ReportPeriodicity,
        customIntervalDays: Int?,
        in context: ModelContext
    ) -> ReportSettings {
        let settings = currentSettings(in: context)
        settings.periodicity = periodicity
        if let customIntervalDays {
            settings.customIntervalDays = customIntervalDays
        }
        settings.nextDueDate = ReportPeriodBoundary.nextDueDate(
            after: .now,
            periodicity: periodicity,
            customIntervalDays: settings.customIntervalDays
        )
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
