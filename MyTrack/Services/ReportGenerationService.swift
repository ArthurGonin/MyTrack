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

    @discardableResult
    func generateReport(
        trips: [Trip],
        periodStart: Date,
        periodEnd: Date,
        source: ReportSource,
        in context: ModelContext
    ) throws -> GeneratedReport {
        let pdfData = TripReportPDFRenderer.render(
            trips: trips,
            periodStart: periodStart,
            periodEnd: periodEnd,
            generatedAt: .now
        )

        let directory = try reportsDirectory()
        let fileName = "report-\(UUID().uuidString).pdf"
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
