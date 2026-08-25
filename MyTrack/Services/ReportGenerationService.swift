//
//  ReportGenerationService.swift
//  MyTrack
//
//  Orchestrates PDF rendering, writing the file under <Documents>/Reports/,
//  and creating the matching GeneratedReport record — kept coupled in one
//  method so there's never a record pointing at a file that failed to write.
//

import Foundation
import SwiftData

final class ReportGenerationService {
    private let reportsDirectoryName = "Reports"
    private let userProfileService: UserProfileService

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(userProfileService: UserProfileService) {
        self.userProfileService = userProfileService
    }

    @discardableResult
    func generateReport(
        trips: [Trip],
        periodStart: Date,
        periodEnd: Date,
        source: ReportSource,
        in context: ModelContext
    ) throws -> GeneratedReport {
        let generatedAt = Date.now
        let pdfData = TripReportPDFRenderer.render(
            trips: trips,
            periodStart: periodStart,
            periodEnd: periodEnd,
            generatedAt: generatedAt
        )

        let directory = try reportsDirectory()
        let profile = userProfileService.currentProfile(in: context)
        let fileName = uniqueFileName(for: profile, generatedAt: generatedAt, in: directory)
        try pdfData.write(to: directory.appendingPathComponent(fileName), options: .atomic)

        let report = GeneratedReport(
            periodStart: periodStart,
            periodEnd: periodEnd,
            fileName: fileName,
            tripCount: trips.count,
            totalDistanceMeters: trips.reduce(0) { $0 + $1.distanceMeters },
            source: source
        )
        context.insert(report)
        try context.save()
        return report
    }

    func fileURL(for report: GeneratedReport) -> URL {
        (try? reportsDirectory())?.appendingPathComponent(report.fileName)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(report.fileName)
    }

    func deleteReport(_ report: GeneratedReport, in context: ModelContext) {
        try? FileManager.default.removeItem(at: fileURL(for: report))
        context.delete(report)
        try? context.save()
    }

    /// Builds a file name like "PrenomNom_25-08-2026_14-30-05.pdf" from the user's
    /// profile and the generation date, appending "-2", "-3", ... on the rare
    /// same-second collision so a report never silently overwrites another.
    private func uniqueFileName(for profile: UserProfile, generatedAt: Date, in directory: URL) -> String {
        let rawName = (profile.firstName + profile.lastName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let name = rawName.isEmpty ? "Rapport" : rawName
        let timestamp = Self.fileNameDateFormatter.string(from: generatedAt)
        let baseName = "\(name)_\(timestamp)"

        var fileName = "\(baseName).pdf"
        var suffix = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            fileName = "\(baseName)-\(suffix).pdf"
            suffix += 1
        }
        return fileName
    }

    private func reportsDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = documents.appendingPathComponent(reportsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
