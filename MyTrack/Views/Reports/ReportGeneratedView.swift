//
//  ReportGeneratedView.swift
//  MyTrack
//
//  Small confirmation sheet shown right after a manual export finishes,
//  opening the PDF directly in-app via QuickLook.
//

import SwiftUI
import SwiftData
import QuickLook

struct ReportGeneratedView: View {
    let report: GeneratedReport
    /// Nil when the file's location can't be resolved — the sheet then just
    /// confirms the report exists instead of failing to open a bogus path.
    let fileURL: URL?
    let onDone: () -> Void

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext

    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Rapport généré")
                    .font(.title2.weight(.semibold))
                Text("\(report.tripCount) trajets")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { onDone() }
                }
            }
            .onAppear {
                previewURL = fileURL
                // The user is being shown the PDF right now, so it mustn't
                // then turn up unopened — with a red dot and a tab badge — in
                // the reports list they land back on.
                appServices.reportGenerationService.markOpened(report, in: modelContext)
            }
            .quickLookPreview($previewURL)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let report = GeneratedReport(
        periodStart: .now.addingTimeInterval(-86400 * 30),
        periodEnd: .now,
        fileName: "preview.pdf",
        tripCount: 12,
        totalDistanceMeters: 240_000,
        source: .manual
    )
    container.mainContext.insert(report)
    return ReportGeneratedView(report: report, fileURL: URL(fileURLWithPath: "/tmp/preview.pdf"), onDone: {})
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
