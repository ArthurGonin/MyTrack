//
//  ReportsView.swift
//  MyTrack
//
//  Third tab: every generated report — manual exports and the ones produced
//  automatically by a periodic profile alike — newest first. A report the user
//  has never opened carries a red dot here and counts towards the badge on the
//  tab itself, which is what replaced the notification bell.
//

import SwiftUI
import SwiftData
import QuickLook

struct ReportsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GeneratedReport.createdAt, order: .reverse) private var reports: [GeneratedReport]

    @State private var previewURL: URL?
    @State private var isPresentingExport = false

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun rapport", systemImage: "doc.text")
                    } description: {
                        Text("Les rapports générés apparaîtront ici, du plus récent au plus ancien.")
                    } actions: {
                        Button("Exporter un rapport") { isPresentingExport = true }
                    }
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
                }
            }
            .appBackground()
            .quickLookPreview($previewURL)
            .navigationTitle("Rapports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingExport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Exporter un rapport")
                }
            }
            .sheet(isPresented: $isPresentingExport) {
                ReportExportView()
            }
            .accountToolbar()
        }
    }

    private func reportRow(_ report: GeneratedReport) -> some View {
        let isUnopened = report.openedAt == nil
        return Button {
            open(report)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Drawn clear rather than dropped when the report has been
                // opened, so read and unread rows keep the same text margin.
                Circle()
                    .fill(isUnopened ? Color.red : Color.clear)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
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
        .accessibilityValue(isUnopened ? "Non ouvert" : "")
    }

    private func open(_ report: GeneratedReport) {
        previewURL = appServices.reportGenerationService.fileURL(for: report)
        appServices.reportGenerationService.markOpened(report, in: modelContext)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let unopened = GeneratedReport(
        periodStart: .now.addingTimeInterval(-86400 * 30),
        periodEnd: .now,
        fileName: "preview.pdf",
        tripCount: 12,
        totalDistanceMeters: 240_000,
        source: .periodic,
        profileName: "Mensuel"
    )
    let opened = GeneratedReport(
        periodStart: .now.addingTimeInterval(-86400 * 60),
        periodEnd: .now.addingTimeInterval(-86400 * 30),
        fileName: "preview-2.pdf",
        tripCount: 4,
        totalDistanceMeters: 88_000,
        source: .manual
    )
    opened.openedAt = .now
    container.mainContext.insert(unopened)
    container.mainContext.insert(opened)
    return ReportsView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
