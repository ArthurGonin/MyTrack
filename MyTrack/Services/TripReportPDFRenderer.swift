//
//  TripReportPDFRenderer.swift
//  MyTrack
//
//  Pure [TripReportRow] -> PDF Data rendering, no ModelContext, no file I/O —
//  kept separate from ReportGenerationService so the drawing code doesn't get
//  entangled with orchestration/persistence. Taking plain snapshot rows rather
//  than SwiftData models is what makes it `nonisolated`, so the whole render
//  can run off the main thread.
//

import Foundation
import UIKit

nonisolated enum TripReportPDFRenderer {
    private static let pageWidth: CGFloat = 595.2
    private static let pageHeight: CGFloat = 841.8
    private static let margin: CGFloat = 40
    private static let rowHeight: CGFloat = 22

    private struct Column {
        let title: String
        let x: CGFloat
        let width: CGFloat
    }

    private static let columns: [Column] = [
        Column(title: "Date", x: margin, width: 130),
        Column(title: "Véhicule", x: margin + 130, width: 140),
        Column(title: "Distance", x: margin + 270, width: 90),
        Column(title: "Durée", x: margin + 360, width: 80),
        Column(title: "Source", x: margin + 440, width: pageWidth - margin - (margin + 440)),
    ]

    /// `rows` are expected already sorted by date — they're snapshotted in
    /// order by ReportGenerationService.
    static func render(
        rows: [TripReportRow],
        periodStart: Date,
        periodEnd: Date,
        generatedAt: Date,
        distanceUnit: DistanceUnit,
        vehicleNames: [String] = []
    ) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: UIGraphicsPDFRendererFormat())

        return renderer.pdfData { context in
            context.beginPage()
            var y = drawFirstPageHeader(
                periodStart: periodStart, periodEnd: periodEnd, generatedAt: generatedAt,
                rows: rows, distanceUnit: distanceUnit, vehicleNames: vehicleNames
            )
            y = drawTableHeader(at: y)

            if rows.isEmpty {
                drawEmptyState(at: y)
            }

            for row in rows {
                if y + rowHeight > pageHeight - margin {
                    context.beginPage()
                    y = drawTableHeader(at: margin)
                }
                draw(row, at: y)
                y += rowHeight
            }
        }
    }

    private static func drawFirstPageHeader(
        periodStart: Date, periodEnd: Date, generatedAt: Date, rows: [TripReportRow],
        distanceUnit: DistanceUnit, vehicleNames: [String]
    ) -> CGFloat {
        var y = margin

        "Rapport de trajets".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)]
        )
        y += 28

        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
        "Période : \(formattedDate(periodStart)) – \(formattedDate(periodEnd))"
            .draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttributes)
        y += 16

        "Généré le \(formattedDateTime(generatedAt))"
            .draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttributes)
        y += 16

        if !vehicleNames.isEmpty {
            "Véhicules : \(vehicleNames.joined(separator: ", "))"
                .draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttributes)
            y += 16
        }
        y += 8

        let totalDistanceMeters = rows.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = rows.reduce(0.0) { $0 + $1.durationSeconds }
        let tripWord = rows.count > 1 ? "trajets" : "trajet"
        let totalDistance = TripFormatting.distance(meters: totalDistanceMeters, unit: distanceUnit)
        let summary = "\(rows.count) \(tripWord) · \(totalDistance) · \(TripFormatting.duration(totalDuration))"
        summary.draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 13)]
        )
        y += 28

        return y
    }

    @discardableResult
    private static func drawTableHeader(at y: CGFloat) -> CGFloat {
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray,
        ]
        for column in columns {
            column.title.draw(
                in: CGRect(x: column.x, y: y, width: column.width, height: rowHeight),
                withAttributes: headerAttributes
            )
        }

        let lineY = y + rowHeight - 4
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: lineY))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: lineY))
        path.lineWidth = 0.5
        UIColor.lightGray.setStroke()
        path.stroke()

        return y + rowHeight
    }

    private static func draw(_ row: TripReportRow, at y: CGFloat) {
        let rowAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let values = [
            row.date,
            row.vehicleName,
            row.distance,
            row.duration,
            row.source,
        ]
        for (index, column) in columns.enumerated() {
            values[index].draw(
                in: CGRect(x: column.x, y: y, width: column.width, height: rowHeight),
                withAttributes: rowAttributes
            )
        }
    }

    private static func drawEmptyState(at y: CGFloat) {
        "Aucun trajet sur cette période.".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12), .foregroundColor: UIColor.gray]
        )
    }

    private static func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func formattedDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
