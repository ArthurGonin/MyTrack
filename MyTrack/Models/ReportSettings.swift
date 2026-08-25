//
//  ReportSettings.swift
//  MyTrack
//

import Foundation
import SwiftData

@Model
final class ReportSettings {
    var periodicity: ReportPeriodicity
    var customIntervalDays: Int
    var nextDueDate: Date?
    var lastGeneratedAt: Date?

    init(
        periodicity: ReportPeriodicity = .none,
        customIntervalDays: Int = 30,
        nextDueDate: Date? = nil,
        lastGeneratedAt: Date? = nil
    ) {
        self.periodicity = periodicity
        self.customIntervalDays = customIntervalDays
        self.nextDueDate = nextDueDate
        self.lastGeneratedAt = lastGeneratedAt
    }
}
