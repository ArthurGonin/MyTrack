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

    @Environment(\.locale) private var locale
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
                        Button("Créer un nouveau rapport") { isPresentingExport = true }
                    }
                } else {
                    List {
                        ForEach(reports) { report in
                            reportRow(report)
                                .appCardRow()
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                appServices.reportGenerationService.deleteReport(reports[index], in: modelContext)
                            }
                        }
                    }
                    // Les lignes portent elles-mêmes leur carte : le style de
                    // liste ne doit pas en dessiner une seconde autour d'elles.
                    .listStyle(.plain)
                }
            }
            .appBackground()
            .quickLookPreview($previewURL)
            .localizedNavigationTitle("Rapports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingExport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Créer un nouveau rapport")
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
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(
                        TripFormatting.shortDate(report.periodStart, locale: locale)
                        + " – "
                        + TripFormatting.shortDate(report.periodEnd, locale: locale)
                    )
                    .font(.subheadline)
                    HStack(spacing: 6) {
                        Text("\(report.tripCount) trajets")
                        Text("·")
                        // Formatted live, so this follows the current setting —
                        // while the PDF it opens keeps the unit it was made
                        // with, being a frozen document. The two can therefore
                        // disagree after a unit change; that's intended.
                        Text(TripFormatting.distance(
                            meters: report.totalDistanceMeters,
                            unit: appServices.unitSettingsService.distanceUnit,
                            locale: locale
                        ))
                        // Le coût, lui, est figé : c'est celui qu'a écrit le
                        // PDF, avec les prix du jour où il a été produit. Rien
                        // n'est affiché pour un rapport qui n'en avait pas.
                        if let totalEnergyCost = report.totalEnergyCost {
                            Text("·")
                            Text(TripFormatting.currency(totalEnergyCost, locale: locale))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isUnopened ? Text("Non ouvert") : Text(""))
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
