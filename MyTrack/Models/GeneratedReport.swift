//
//  GeneratedReport.swift
//  MyTrack
//
//  A record of a PDF report already written to disk (under
//  <Documents>/Reports/). Only the relative file name is stored — the
//  Documents directory path itself can change between installs/updates, so
//  the full URL is always reconstructed at read time.
//

import Foundation
import SwiftData

@Model
final class GeneratedReport {
    var id: UUID
    var createdAt: Date
    var periodStart: Date
    var periodEnd: Date
    var fileName: String
    var tripCount: Int
    var totalDistanceMeters: Double
    var source: ReportSource

    init(
        periodStart: Date,
        periodEnd: Date,
        fileName: String,
        tripCount: Int,
        totalDistanceMeters: Double,
        source: ReportSource
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.fileName = fileName
        self.tripCount = tripCount
        self.totalDistanceMeters = totalDistanceMeters
        self.source = source
    }
}
