//
//  ReportGenerationService.swift
//  MyTrack
//
//  Orchestrates PDF rendering, writing the file under <Documents>/Reports/,
//  and creating the matching GeneratedReport record — kept coupled in one
//  method so there's never a record pointing at a file that failed to write.
//

import Foundation
import OSLog
import SwiftData

final class ReportGenerationService {
    private let reportsDirectoryName = "Reports"
    private let userProfileService: UserProfileService
    private let unitSettingsService: UnitSettingsService
    private let languageService: LanguageService

    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(
        userProfileService: UserProfileService,
        unitSettingsService: UnitSettingsService,
        languageService: LanguageService
    ) {
        self.userProfileService = userProfileService
        self.unitSettingsService = unitSettingsService
        self.languageService = languageService
    }

    /// Rendering a long report — hundreds of rows across several pages — takes
    /// long enough to drop frames, so the drawing and the file write happen off
    /// the main thread. The trips are snapshotted into `TripReportRow` values
    /// first, because SwiftData models can't be read from another thread.
    @discardableResult
    func generateReport(
        trips: [Trip],
        periodStart: Date,
        periodEnd: Date,
        source: ReportSource,
        profileName: String? = nil,
        includedVehicles: [Vehicle] = [],
        pendingTripCount: Int = 0,
        in context: ModelContext
    ) async throws -> GeneratedReport {
        let generatedAt = Date.now
        let includedVehicleNames = includedVehicles.map(\.name)
        let totalDistanceMeters = trips.reduce(0) { $0 + $1.distanceMeters }
        // Read once here, on the main actor: the PDF is a frozen document, so
        // it keeps the unit in force when it was produced even if the user
        // switches afterwards.
        let distanceUnit = unitSettingsService.distanceUnit
        // Même raison pour la langue que pour l'unité : le PDF est un document
        // figé, il garde celle dans laquelle il a été écrit.
        let locale = languageService.locale
        let bundle = languageService.bundle
        let rows = trips
            .sorted { $0.startDate < $1.startDate }
            .map { TripReportRow(trip: $0, unit: distanceUnit, locale: locale) }

        let directory = try reportsDirectory()
        let userProfile = userProfileService.currentProfile(in: context)
        let fileName = uniqueFileName(for: userProfile, generatedAt: generatedAt, in: directory)
        let fileURL = directory.appendingPathComponent(fileName)

        try await Task.detached(priority: .userInitiated) {
            let pdfData = TripReportPDFRenderer.render(
                rows: rows,
                periodStart: periodStart,
                periodEnd: periodEnd,
                generatedAt: generatedAt,
                distanceUnit: distanceUnit,
                locale: locale,
                bundle: bundle,
                vehicleNames: includedVehicleNames,
                pendingTripCount: pendingTripCount
            )
            try pdfData.write(to: fileURL, options: .atomic)
        }.value

        let report = GeneratedReport(
            periodStart: periodStart,
            periodEnd: periodEnd,
            fileName: fileName,
            tripCount: rows.count,
            totalDistanceMeters: totalDistanceMeters,
            source: source,
            profileName: profileName,
            includedVehicleNames: includedVehicleNames
        )
        context.insert(report)
        try context.save()
        return report
    }

    /// `nil` when the Documents directory can't be reached: the caller then has
    /// nothing to open or delete, rather than being handed a path that was
    /// never written to and failing later with "file not found".
    func fileURL(for report: GeneratedReport) -> URL? {
        guard let directory = try? reportsDirectory() else {
            AppLog.reports.error("Reports directory unavailable — no URL for \(report.fileName, privacy: .public).")
            return nil
        }
        return directory.appendingPathComponent(report.fileName)
    }

    /// Clears the report's unopened marker. Idempotent, so re-opening an old
    /// report doesn't churn a save for nothing.
    func markOpened(_ report: GeneratedReport, in context: ModelContext) {
        guard report.openedAt == nil else { return }
        report.openedAt = .now
        context.saveOrLog()
    }

    func deleteReport(_ report: GeneratedReport, in context: ModelContext) {
        if let url = fileURL(for: report) {
            // A file that's already gone isn't worth reporting: the record is
            // being removed either way.
            try? FileManager.default.removeItem(at: url)
        }
        context.delete(report)
        context.saveOrLog()
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
