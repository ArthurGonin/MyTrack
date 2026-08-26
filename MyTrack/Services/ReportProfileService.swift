//
//  ReportProfileService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class ReportProfileService {
    func allProfiles(in context: ModelContext) -> [ReportProfile] {
        let descriptor = FetchDescriptor<ReportProfile>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createProfile(name: String, in context: ModelContext) -> ReportProfile {
        let profile = ReportProfile(name: name)
        context.insert(profile)
        try? context.save()
        return profile
    }

    func deleteProfile(_ profile: ReportProfile, in context: ModelContext) {
        context.delete(profile)
        try? context.save()
    }

    @discardableResult
    func updateName(_ name: String, for profile: ReportProfile, in context: ModelContext) -> ReportProfile {
        profile.name = name
        try? context.save()
        return profile
    }

    /// Switches the active periodicity. For `.custom`, the interval and the next due date
    /// are chosen separately by the user (see `updateCustomInterval` and
    /// `updateCustomNextDueDate`), so this only seeds a default next due date the first
    /// time `.custom` is selected — it never overwrites a date the user already picked.
    @discardableResult
    func updatePeriodicity(_ periodicity: ReportPeriodicity, for profile: ReportProfile, in context: ModelContext) -> ReportProfile {
        let periodicityChanged = profile.periodicity != periodicity
        profile.periodicity = periodicity
        if periodicity != .custom || periodicityChanged {
            profile.nextDueDate = ReportPeriodBoundary.nextDueDate(
                after: .now,
                periodicity: periodicity,
                customIntervalDays: profile.customIntervalDays
            )
        }
        try? context.save()
        return profile
    }

    /// Sets how often a custom-schedule report repeats, without touching the next due
    /// date the user picked.
    @discardableResult
    func updateCustomInterval(days: Int, for profile: ReportProfile, in context: ModelContext) -> ReportProfile {
        profile.periodicity = .custom
        profile.customIntervalDays = max(1, days)
        try? context.save()
        return profile
    }

    /// Sets the exact date/time of the next custom-schedule report, as chosen by the user.
    @discardableResult
    func updateCustomNextDueDate(_ date: Date, for profile: ReportProfile, in context: ModelContext) -> ReportProfile {
        profile.periodicity = .custom
        profile.nextDueDate = date
        try? context.save()
        return profile
    }

    @discardableResult
    func updateVehicles(_ vehicles: [Vehicle], for profile: ReportProfile, in context: ModelContext) -> ReportProfile {
        profile.vehicles = vehicles
        try? context.save()
        return profile
    }

    /// Returns the trip window to generate a report for, if a periodic report is due, `nil` otherwise.
    func periodDueForGeneration(profile: ReportProfile, now: Date) -> (periodStart: Date, periodEnd: Date)? {
        guard profile.periodicity != .none, let nextDueDate = profile.nextDueDate, now >= nextDueDate else {
            return nil
        }
        let range = ReportPeriodBoundary.periodRange(
            endingAt: nextDueDate,
            periodicity: profile.periodicity,
            customIntervalDays: profile.customIntervalDays
        )
        return (range.start, range.end)
    }

    /// Call after a periodic report was successfully generated through `periodEnd`.
    /// Returns the new due date so the caller can reschedule the "report ready" notification.
    @discardableResult
    func advanceAfterGeneration(profile: ReportProfile, generatedThrough periodEnd: Date, in context: ModelContext) -> Date? {
        profile.lastGeneratedAt = periodEnd
        profile.nextDueDate = ReportPeriodBoundary.nextDueDate(
            after: periodEnd,
            periodicity: profile.periodicity,
            customIntervalDays: profile.customIntervalDays
        )
        try? context.save()
        return profile.nextDueDate
    }
}
