//
//  ReportExportView.swift
//  MyTrack
//
//  Manual PDF export sheet presented from TripListView: either a date range
//  (auto-selects confirmed trips in that window) or a manual multi-select
//  list of confirmed trips.
//

import SwiftUI
import OSLog
import SwiftData

struct ReportExportView: View {
    private enum ExportMode: CaseIterable, Hashable {
        case dateRange
        case manualSelection

        var label: LocalizedStringKey {
            switch self {
            case .dateRange: "Plage de dates"
            case .manualSelection: "Sélection manuelle"
            }
        }
    }

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Query(sort: \Trip.startDate, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Vehicle.name) private var allVehicles: [Vehicle]

    @State private var mode: ExportMode = .dateRange
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var endDate = Date.now
    @State private var selectedTripIDs: Set<PersistentIdentifier> = []
    @State private var selectedVehicleIDs: Set<PersistentIdentifier> = []
    @State private var generatedReport: GeneratedReport?
    @State private var isGenerationFailedAlertPresented = false
    @State private var isGenerating = false

    private var confirmedTrips: [Trip] {
        allTrips
            .filter { $0.confirmationStatus == .confirmed }
            .filter(matchesSelectedVehicles)
    }

    /// Trips inside the chosen window that can't be included because they're
    /// still awaiting confirmation. Counted only for the date-range mode: a
    /// manual selection can only ever pick from confirmed trips, so nothing is
    /// being left out behind the user's back there.
    private var pendingTripCount: Int {
        guard mode == .dateRange else { return 0 }
        return allTrips
            .filter { $0.confirmationStatus == .pendingConfirmation }
            .filter(matchesSelectedVehicles)
            .filter { $0.startDate >= dateRangeStart && $0.startDate < dateRangeEnd }
            .count
    }

    private func matchesSelectedVehicles(_ trip: Trip) -> Bool {
        guard !selectedVehicleIDs.isEmpty else { return true }
        guard let vehicle = trip.vehicle else { return false }
        return selectedVehicleIDs.contains(vehicle.persistentModelID)
    }

    /// Deux phrases traduites séparément plutôt qu'une seule à trous : chacune
    /// n'a alors qu'un nombre, donc un pluriel que le catalogue sait accorder
    /// dans chaque langue.
    private var dateRangeFooter: String {
        var text = String(localized: "\(tripsToExport.count) trajets sur cette période.", locale: locale)
        if pendingTripCount > 0 {
            text += " " + String(
                localized: "\(pendingTripCount) autres en attente de confirmation, non inclus.",
                locale: locale
            )
        }
        return text
    }

    private var includedVehicles: [Vehicle] {
        allVehicles.filter { selectedVehicleIDs.contains($0.persistentModelID) }
    }

    private var tripsToExport: [Trip] {
        switch mode {
        case .dateRange:
            return confirmedTrips.filter { $0.startDate >= dateRangeStart && $0.startDate < dateRangeEnd }
        case .manualSelection:
            return confirmedTrips.filter { selectedTripIDs.contains($0.persistentModelID) }
        }
    }

    /// The pickers only offer days, so the range covers whole days. Using the
    /// raw picker values would silently cut the end day off at whatever time of
    /// day it happened to carry, dropping that afternoon's trips.
    private var dateRangeStart: Date {
        Calendar.current.startOfDay(for: startDate)
    }

    private var dateRangeEnd: Date {
        let startOfEndDay = Calendar.current.startOfDay(for: endDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfEndDay) ?? startOfEndDay
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(ExportMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                if !allVehicles.isEmpty {
                    Section {
                        vehicleSelectionRow(title: Text("Tous les véhicules"), isSelected: selectedVehicleIDs.isEmpty) {
                            selectedVehicleIDs.removeAll()
                        }
                        ForEach(allVehicles) { vehicle in
                            vehicleSelectionRow(
                                title: Text(vehicle.name),
                                isSelected: selectedVehicleIDs.contains(vehicle.persistentModelID)
                            ) {
                                toggleVehicle(vehicle)
                            }
                        }
                    } header: {
                        Text("Véhicules")
                    }
                }

                switch mode {
                case .dateRange:
                    Section {
                        DatePicker("Début", selection: $startDate, displayedComponents: .date)
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    } footer: {
                        Text(dateRangeFooter)
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
            .navigationTitle("Nouveau rapport")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Button("Générer") { generate() }
                            .disabled(tripsToExport.isEmpty)
                    }
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
                    Group {
                        if let name = trip.vehicle?.name {
                            Text(name)
                        } else {
                            Text("Aucun véhicule")
                        }
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(trip.formattedDistance(
                    in: appServices.unitSettingsService.distanceUnit, locale: locale
                ))
                    .foregroundStyle(.secondary)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Le titre arrive déjà sous forme de `Text` : un nom de véhicule est une
    /// donnée saisie, qui se rend telle quelle, tandis que « Tous les
    /// véhicules » est du texte d'interface, qui se traduit.
    private func vehicleSelectionRow(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleVehicle(_ vehicle: Vehicle) {
        if selectedVehicleIDs.contains(vehicle.persistentModelID) {
            selectedVehicleIDs.remove(vehicle.persistentModelID)
        } else {
            selectedVehicleIDs.insert(vehicle.persistentModelID)
        }
    }

    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true

        let trips = tripsToExport
        let vehicles = includedVehicles
        let start = periodStart
        let end = periodEnd
        let pending = pendingTripCount

        Task {
            do {
                generatedReport = try await appServices.reportGenerationService.generateReport(
                    trips: trips,
                    periodStart: start,
                    periodEnd: end,
                    source: .manual,
                    includedVehicles: vehicles,
                    pendingTripCount: pending,
                    in: modelContext
                )
            } catch {
                AppLog.reports.error("Manual export failed: \(error.localizedDescription, privacy: .public)")
                isGenerationFailedAlertPresented = true
            }
            isGenerating = false
        }
    }

    private var periodStart: Date {
        switch mode {
        case .dateRange: return dateRangeStart
        case .manualSelection: return tripsToExport.map(\.startDate).min() ?? .now
        }
    }

    private var periodEnd: Date {
        switch mode {
        case .dateRange: return dateRangeEnd
        case .manualSelection: return tripsToExport.map { $0.endDate ?? $0.startDate }.max() ?? .now
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ReportExportView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
