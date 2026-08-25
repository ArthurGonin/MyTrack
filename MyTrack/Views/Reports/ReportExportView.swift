//
//  ReportExportView.swift
//  MyTrack
//
//  Manual PDF export sheet presented from TripListView: either a date range
//  (auto-selects confirmed trips in that window) or a manual multi-select
//  list of confirmed trips.
//

import SwiftUI
import SwiftData

struct ReportExportView: View {
    private enum ExportMode: String, CaseIterable, Hashable {
        case dateRange = "Plage de dates"
        case manualSelection = "Sélection manuelle"
    }

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Trip.startDate, order: .reverse) private var allTrips: [Trip]

    @State private var mode: ExportMode = .dateRange
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date.now
    @State private var selectedTripIDs: Set<PersistentIdentifier> = []
    @State private var generatedReport: GeneratedReport?
    @State private var isGenerationFailedAlertPresented = false

    private var confirmedTrips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .confirmed }
    }

    private var tripsToExport: [Trip] {
        switch mode {
        case .dateRange:
            return confirmedTrips.filter { $0.startDate >= startDate && $0.startDate < endDate }
        case .manualSelection:
            return confirmedTrips.filter { selectedTripIDs.contains($0.persistentModelID) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(ExportMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch mode {
                case .dateRange:
                    Section {
                        DatePicker("Début", selection: $startDate, displayedComponents: .date)
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    } footer: {
                        Text("\(tripsToExport.count) trajet\(tripsToExport.count > 1 ? "s" : "") sur cette période.")
                    }
                case .manualSelection:
                    Section {
                        if confirmedTrips.isEmpty {
                            ContentUnavailableView("Aucun trajet", systemImage: "map")
                        } else {
                            ForEach(confirmedTrips) { trip in
                                tripSelectionRow(trip)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Exporter un rapport")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Générer") { generate() }
                        .disabled(tripsToExport.isEmpty)
                }
            }
            .alert("Échec de la génération", isPresented: $isGenerationFailedAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Le rapport n'a pas pu être créé. Réessaie plus tard.")
            }
            .sheet(item: $generatedReport) { report in
                ReportGeneratedView(
                    report: report,
                    fileURL: appServices.reportGenerationService.fileURL(for: report),
                    onDone: { dismiss() }
                )
            }
        }
    }

    private func tripSelectionRow(_ trip: Trip) -> some View {
        let isSelected = selectedTripIDs.contains(trip.persistentModelID)
        return Button {
            if isSelected {
                selectedTripIDs.remove(trip.persistentModelID)
            } else {
                selectedTripIDs.insert(trip.persistentModelID)
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(trip.startDate, style: .date)
                        .foregroundStyle(.primary)
                    Text(trip.vehicle?.name ?? "Aucun véhicule")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(trip.formattedDistance)
                    .foregroundStyle(.secondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func generate() {
        do {
            generatedReport = try appServices.reportGenerationService.generateReport(
                trips: tripsToExport,
                periodStart: periodStart,
                periodEnd: periodEnd,
                source: .manual,
                in: modelContext
            )
        } catch {
            isGenerationFailedAlertPresented = true
        }
    }

    private var periodStart: Date {
        switch mode {
        case .dateRange: return startDate
        case .manualSelection: return tripsToExport.map(\.startDate).min() ?? .now
        }
    }

    private var periodEnd: Date {
        switch mode {
        case .dateRange: return endDate
        case .manualSelection: return tripsToExport.map { $0.endDate ?? $0.startDate }.max() ?? .now
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportSettings.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ReportExportView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
