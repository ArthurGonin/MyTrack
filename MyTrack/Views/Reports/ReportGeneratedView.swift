//
//  ReportGeneratedView.swift
//  MyTrack
//
//  Small confirmation sheet shown right after a manual export finishes,
//  offering an immediate share via the native share sheet.
//

import SwiftUI

struct ReportGeneratedView: View {
    let report: GeneratedReport
    let fileURL: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Rapport généré")
                    .font(.title2.weight(.semibold))
                Text("\(report.tripCount) trajet\(report.tripCount > 1 ? "s" : "")")
                    .foregroundStyle(.secondary)
                ShareLink(item: fileURL) {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { onDone() }
                }
            }
        }
    }
}

#Preview {
    let report = GeneratedReport(
        periodStart: .now.addingTimeInterval(-86400 * 30),
        periodEnd: .now,
        fileName: "preview.pdf",
        tripCount: 12,
        totalDistanceMeters: 240_000,
        source: .manual
    )
    return ReportGeneratedView(report: report, fileURL: URL(fileURLWithPath: "/tmp/preview.pdf"), onDone: {})
}
