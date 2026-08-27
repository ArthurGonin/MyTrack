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
    private static let brandIconSide: CGFloat = 44
    /// Rule + padding + the row itself, so the totals never land on a page
    /// without the rows they sum.
    private static let totalsHeight: CGFloat = rowHeight + 12
    private static let pendingNoticeHeight: CGFloat = 30
    /// The strip at the foot of every page holding "1/3". Reserved whether or
    /// not the number is drawn yet — see `render` — so that both layout passes
    /// break pages at the same rows.
    private static let footerHeight: CGFloat = 24

    /// The lowest y content may occupy before it has to move to a new page.
    private static var contentBottom: CGFloat { pageHeight - margin - footerHeight }

    private struct Column {
        let title: String
        let width: CGFloat
        var x: CGFloat = 0
    }

    /// Only widths are declared; the x offsets are derived by `laidOut` so that
    /// widening one column doesn't mean re-deriving the position of every
    /// column after it by hand. The widths add up to the printable width
    /// (`pageWidth - 2 * margin`).
    private static let columns: [Column] = laidOut([
        Column(title: "Date", width: 150),
        Column(title: "Véhicule", width: 175.2),
        Column(title: "Distance", width: 100),
        Column(title: "Durée", width: 90),
    ])

    private static func laidOut(_ columns: [Column]) -> [Column] {
        var x = margin
        return columns.map { column in
            var positioned = column
            positioned.x = x
            x += column.width
            return positioned
        }
    }

    /// `rows` are expected already sorted by date — they're snapshotted in
    /// order by ReportGenerationService.
    /// `pendingTripCount` is how many trips fall in the period but are still
    /// awaiting confirmation, and are therefore absent from `rows`. Stated on
    /// the document rather than dropped in silence: a mileage total that is
    /// quietly short is worse than one that says what it left out.
    static func render(
        rows: [TripReportRow],
        periodStart: Date,
        periodEnd: Date,
        generatedAt: Date,
        distanceUnit: DistanceUnit,
        vehicleNames: [String] = [],
        pendingTripCount: Int = 0
    ) -> Data {
        let document = Document(
            rows: rows,
            periodStart: periodStart,
            periodEnd: periodEnd,
            generatedAt: generatedAt,
            distanceUnit: distanceUnit,
            vehicleNames: vehicleNames,
            pendingTripCount: pendingTripCount,
            // Looked up once, outside the drawing passes: it's the same image
            // on every page, and the lookup reaches into the bundle.
            icon: appIcon()
        )

        // "1/3" can't be written before the last page is known, and a PDF page
        // can't be revisited once the next one has begun. So the layout runs
        // twice: a first pass whose output is thrown away purely to count the
        // pages, then the real one with the count in hand. Running the same
        // code both times — rather than predicting the page count from the row
        // count — is what guarantees the two agree; a header line that appears
        // only for some reports would otherwise be enough to skew the maths.
        //
        // A fresh renderer per pass: a UIGraphicsPDFRenderer yields its
        // document once, and answers a second `pdfData` with empty Data.
        var pageCount = 0
        _ = makeRenderer().pdfData { context in
            pageCount = draw(document, in: context, pageCount: nil)
        }

        return makeRenderer().pdfData { context in
            _ = draw(document, in: context, pageCount: pageCount)
        }
    }

    private static func makeRenderer() -> UIGraphicsPDFRenderer {
        UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: UIGraphicsPDFRendererFormat()
        )
    }

    /// Everything the layout reads, gathered so the two passes are handed
    /// identical input by construction.
    private struct Document {
        let rows: [TripReportRow]
        let periodStart: Date
        let periodEnd: Date
        let generatedAt: Date
        let distanceUnit: DistanceUnit
        let vehicleNames: [String]
        let pendingTripCount: Int
        let icon: UIImage?
    }

    /// Lays the whole report out and returns how many pages it took.
    /// `pageCount` is nil on the counting pass, when the footer's total isn't
    /// known yet: the strip is still reserved, only left blank.
    private static func draw(
        _ document: Document, in context: UIGraphicsPDFRendererContext, pageCount: Int?
    ) -> Int {
        var pageNumber = 0
        var y: CGFloat = margin

        func beginPage() {
            context.beginPage()
            pageNumber += 1
            if let pageCount {
                drawFooter(page: pageNumber, of: pageCount)
            }
        }

        beginPage()
        y = drawBrandBanner(at: y, distanceUnit: document.distanceUnit, icon: document.icon)
        y = drawDocumentHeader(
            at: y, periodStart: document.periodStart, periodEnd: document.periodEnd,
            generatedAt: document.generatedAt, vehicleNames: document.vehicleNames
        )
        y = drawTableHeader(at: y)

        // Continuing the table on a fresh page repeats the column titles, so a
        // page read on its own still says what each column holds.
        func continueOnNewPageIfNeeded(for height: CGFloat) {
            guard y + height > contentBottom else { return }
            beginPage()
            y = drawTableHeader(at: margin)
        }

        // The totals and the note qualifying them close the report as one
        // block: the note exists to explain that figure, and a page carrying
        // nothing but the sentence reads like a printing accident.
        let noticeHeight = document.pendingTripCount > 0 ? pendingNoticeHeight : 0

        if document.rows.isEmpty {
            y = drawEmptyState(at: y)
        } else {
            for row in document.rows {
                continueOnNewPageIfNeeded(for: rowHeight)
                draw(row, at: y)
                y += rowHeight
            }
            continueOnNewPageIfNeeded(for: totalsHeight + noticeHeight)
            y = drawTotals(at: y, rows: document.rows, distanceUnit: document.distanceUnit)
        }

        if document.pendingTripCount > 0 {
            drawPendingNotice(
                at: y, count: document.pendingTripCount, hasTotals: !document.rows.isEmpty
            )
        }

        return pageNumber
    }

    /// "1/3", centred at the foot of the page — and "1/1" on a single-page
    /// report, so a page always says where it sits and a reader can tell a
    /// complete report from one that lost its second sheet.
    private static func drawFooter(page: Int, of pageCount: Int) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        "\(page)/\(pageCount)".draw(
            in: CGRect(
                x: margin, y: pageHeight - margin - footerHeight + 6,
                width: pageWidth - 2 * margin, height: footerHeight
            ),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.gray,
                .paragraphStyle: paragraph,
            ]
        )
    }

    // MARK: - Branding

    /// The strip at the very top of the first page: the app icon and its name.
    /// The wording follows the distance unit picked in Settings — kilometres
    /// read as French, miles as English — so the line a reader sees first
    /// matches the units it sits above.
    private static func drawBrandBanner(at y: CGFloat, distanceUnit: DistanceUnit, icon: UIImage?) -> CGFloat {
        let iconRect = CGRect(x: margin, y: y, width: brandIconSide, height: brandIconSide)
        drawAppIcon(icon, in: iconRect)

        let tagline: String
        switch distanceUnit {
        case .kilometers: tagline = "Suivi kilométrique : "
        case .miles: tagline = "Mileage tracker: "
        }
        let branding = NSMutableAttributedString(
            string: tagline,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.darkGray,
            ]
        )
        branding.append(NSAttributedString(
            string: appName,
            attributes: [.font: UIFont.boldSystemFont(ofSize: 17)]
        ))
        let brandingSize = branding.size()
        branding.draw(at: CGPoint(x: iconRect.maxX + 12, y: iconRect.midY - brandingSize.height / 2))

        let ruleY = iconRect.maxY + 12
        drawRule(atY: ruleY, width: 0.5, color: .lightGray)
        return ruleY + 16
    }

    /// Draws the icon masked to the rounded square iOS uses on the home screen.
    /// There is no icon in the asset catalog yet, so until one is added the
    /// same square is outlined empty: the space is already reserved, and
    /// nothing below shifts on the day the icon lands.
    private static func drawAppIcon(_ icon: UIImage?, in rect: CGRect) {
        // Apple's icon mask rounds at ~22.4% of the side.
        let mask = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.2237)
        guard let icon else {
            UIColor(white: 0.85, alpha: 1).setStroke()
            mask.lineWidth = 1
            mask.stroke()
            return
        }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        mask.addClip()
        icon.draw(in: rect)
        context.restoreGState()
    }

    private static var appName: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "MyTrack"
    }

    /// The app icon isn't reachable by asset name on every iOS version, so the
    /// bundle's own icon file list is tried first and the asset name only as a
    /// fallback. `nil` — the case today — is expected, not an error.
    private static func appIcon() -> UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           // Last entry is the largest, so the PDF gets the sharpest source.
           let name = files.last,
           let image = UIImage(named: name) {
            return image
        }
        return UIImage(named: "AppIcon")
    }

    // MARK: - Document header

    private static func drawDocumentHeader(
        at y: CGFloat, periodStart: Date, periodEnd: Date, generatedAt: Date, vehicleNames: [String]
    ) -> CGFloat {
        var y = y

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

        return y + 16
    }

    // MARK: - Table

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

        drawRule(atY: y + rowHeight - 4, width: 0.5, color: .lightGray)
        return y + rowHeight
    }

    private static func draw(_ row: TripReportRow, at y: CGFloat) {
        draw(
            values: [row.date, row.vehicleName, row.distance, row.duration],
            at: y,
            attributes: [.font: UIFont.systemFont(ofSize: 11)]
        )
    }

    /// The period totals, closing the table instead of opening the document:
    /// each figure sits directly under the column it sums, so the total
    /// distance reads down the Distance column and the total time down Durée.
    private static func drawTotals(at y: CGFloat, rows: [TripReportRow], distanceUnit: DistanceUnit) -> CGFloat {
        var y = y + 4
        drawRule(atY: y, width: 0.8, color: .darkGray)
        y += 8

        let totalDistanceMeters = rows.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = rows.reduce(0.0) { $0 + $1.durationSeconds }
        let tripWord = rows.count > 1 ? "trajets" : "trajet"
        draw(
            values: [
                "Total (\(rows.count) \(tripWord))",
                "",
                TripFormatting.distance(meters: totalDistanceMeters, unit: distanceUnit),
                TripFormatting.duration(totalDuration),
            ],
            at: y,
            attributes: [.font: UIFont.boldSystemFont(ofSize: 12)]
        )
        return y + rowHeight
    }

    /// One value per column, in column order.
    private static func draw(values: [String], at y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        for (column, value) in zip(columns, values) {
            value.draw(
                in: CGRect(x: column.x, y: y, width: column.width, height: rowHeight),
                withAttributes: attributes
            )
        }
    }

    @discardableResult
    private static func drawEmptyState(at y: CGFloat) -> CGFloat {
        "Aucun trajet sur cette période.".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12), .foregroundColor: UIColor.gray]
        )
        return y + rowHeight
    }

    /// `hasTotals` is false when the period held nothing but pending trips:
    /// there is no total above to point at, so the note says the trips are
    /// missing from the report rather than from a figure that isn't there.
    private static func drawPendingNotice(at y: CGFloat, count: Int, hasTotals: Bool) {
        let notice: String
        switch (count > 1, hasTotals) {
        case (true, true):
            notice = "\(count) trajets de cette période sont encore en attente de confirmation : ils ne sont pas comptés dans ce total."
        case (true, false):
            notice = "\(count) trajets de cette période sont encore en attente de confirmation : ils ne figurent pas dans ce rapport."
        case (false, true):
            notice = "1 trajet de cette période est encore en attente de confirmation : il n'est pas compté dans ce total."
        case (false, false):
            notice = "1 trajet de cette période est encore en attente de confirmation : il ne figure pas dans ce rapport."
        }
        notice.draw(
            in: CGRect(x: margin, y: y + 8, width: pageWidth - 2 * margin, height: pendingNoticeHeight),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor(red: 0.60, green: 0.32, blue: 0.02, alpha: 1),
            ]
        )
    }

    // MARK: - Primitives

    private static func drawRule(atY y: CGFloat, width: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private static func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func formattedDateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
