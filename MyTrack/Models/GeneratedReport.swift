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
    var profileName: String?
    var includedVehicleNames: [String]
    /// Nil until the user actually opens the PDF — what drives the red dot in
    /// the reports list and the badge on the Rapports tab. A date rather than a
    /// `Bool` so an existing store picks the property up as a plain optional,
    /// with no migration plan needed.
    var openedAt: Date?

    init(
        periodStart: Date,
        periodEnd: Date,
        fileName: String,
        tripCount: Int,
        totalDistanceMeters: Double,
        source: ReportSource,
        profileName: String? = nil,
        includedVehicleNames: [String] = []
    ) {
        self.id = UUID()
        self.createdAt = .now
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.fileName = fileName
        self.tripCount = tripCount
        self.totalDistanceMeters = totalDistanceMeters
        self.source = source
        self.profileName = profileName
        self.includedVehicleNames = includedVehicleNames
    }
}
