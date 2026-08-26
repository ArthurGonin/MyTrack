//
//  ReportProfile.swift
//  MyTrack
//

import Foundation
import SwiftData

@Model
final class ReportProfile {
    var id: UUID
    var name: String
    var createdAt: Date
    var periodicity: ReportPeriodicity
    var customIntervalDays: Int
    var nextDueDate: Date?
    var lastGeneratedAt: Date?

    @Relationship(deleteRule: .nullify)
    var vehicles: [Vehicle] = []

    init(
        name: String,
        periodicity: ReportPeriodicity = .none,
        customIntervalDays: Int = 30,
        nextDueDate: Date? = nil,
        lastGeneratedAt: Date? = nil,
        vehicles: [Vehicle] = []
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.periodicity = periodicity
        self.customIntervalDays = customIntervalDays
        self.nextDueDate = nextDueDate
        self.lastGeneratedAt = lastGeneratedAt
        self.vehicles = vehicles
    }
}
