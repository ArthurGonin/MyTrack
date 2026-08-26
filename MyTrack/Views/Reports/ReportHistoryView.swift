//
//  ReportHistoryView.swift
//  MyTrack
//
//  Lists every generated report (manual + periodic), reachable from Account
//  Settings — the only place periodic reports become discoverable after
//  they're auto-generated at launch.
//

import SwiftUI
import SwiftData
import QuickLook

struct ReportHistoryView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GeneratedReport.createdAt, order: .reverse) private var reports: [GeneratedReport]

    @State private var previewURL: URL?

    var body: some View {
        Group {
            if reports.isEmpty {
                ContentUnavailableView(
                    "Aucun rapport",
                    systemImage: "doc.text",
                    description: Text("Les rapports générés apparaîtront ici.")
                )
            } else {
                List {
                    ForEach(reports) { report in
                        reportRow(report)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appServices.reportGenerationService.deleteReport(reports[index], in: modelContext)
                        }
                    }
                }
                .quickLookPreview($previewURL)
            }
        }
        .navigationTitle("Rapports")
    }

    private func reportRow(_ report: GeneratedReport) -> some View {
        Button {
            previewURL = appServices.reportGenerationService.fileURL(for: report)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let profileName = report.profileName {
                        Text(profileName)
                            .font(.subheadline.weight(.medium))
                    }
                    Text(
                        "\(report.periodStart.formatted(date: .abbreviated, time: .omitted)) – "
                        + report.periodEnd.formatted(date: .abbreviated, time: .omitted)
                    )
                    HStack(spacing: 6) {
                        Text("\(report.tripCount) trajet\(report.tripCount > 1 ? "s" : "")")
                        Text("·")
                        // Formatted live, so this follows the current setting —
                        // while the PDF it opens keeps the unit it was made
                        // with, being a frozen document. The two can therefore
                        // disagree after a unit change; that's intended.
                        Text(TripFormatting.distance(
                            meters: report.totalDistanceMeters,
                            unit: appServices.unitSettingsService.distanceUnit
                        ))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(
                        report.includedVehicleNames.isEmpty
                            ? "Tous les véhicules"
                            : report.includedVehicleNames.joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return NavigationStack {
        ReportHistoryView()
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
