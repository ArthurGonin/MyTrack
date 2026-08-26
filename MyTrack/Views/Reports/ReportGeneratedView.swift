//
//  ReportGeneratedView.swift
//  MyTrack
//
//  Small confirmation sheet shown right after a manual export finishes,
//  opening the PDF directly in-app via QuickLook.
//

import SwiftUI
import QuickLook

struct ReportGeneratedView: View {
    let report: GeneratedReport
    /// Nil when the file's location can't be resolved — the sheet then just
    /// confirms the report exists instead of failing to open a bogus path.
    let fileURL: URL?
    let onDone: () -> Void

    @State private var previewURL: URL?

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
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { onDone() }
                }
            }
            .onAppear { previewURL = fileURL }
            .quickLookPreview($previewURL)
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
