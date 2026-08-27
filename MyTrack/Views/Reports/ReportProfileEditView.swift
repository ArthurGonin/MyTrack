//
//  ReportProfileEditView.swift
//  MyTrack
//
//  Edits one periodic report profile: its name, frequency, and which
//  vehicles it covers. Every control saves immediately through
//  ReportProfileService, same live-edit pattern the rest of the app uses.
//

import SwiftUI
import SwiftData

struct ReportProfileEditView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    let profile: ReportProfile

    @Query(sort: \Vehicle.name) private var allVehicles: [Vehicle]
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        Form {
            Section {
                TextField("Nom du profil", text: Binding(
                    get: { profile.name },
                    set: { updateName($0) }
                ))
            }
            Section {
                Picker("Fréquence", selection: Binding(
                    get: { profile.periodicity },
                    set: { updatePeriodicity($0) }
                )) {
                    ForEach(ReportPeriodicity.allCases, id: \.self) { periodicity in
                        Text(label(for: periodicity)).tag(periodicity)
                    }
                }
                if profile.periodicity != .none, profile.periodicity != .custom, let nextDueDate = profile.nextDueDate {
                    Text("Le prochain rapport sera envoyé le \(TripFormatting.longDate(nextDueDate, locale: locale))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if profile.periodicity == .custom {
                    Stepper(
                        "Tous les \(profile.customIntervalDays) jours",
                        value: Binding(
                            get: { profile.customIntervalDays },
                            set: { updateCustomInterval($0) }
                        ),
                        in: 1...365
                    )
                    DatePicker(
                        "Prochain rapport",
                        selection: Binding(
                            get: { profile.nextDueDate ?? .now },
                            set: { updateCustomNextDueDate($0) }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            } footer: {
                Text("Génère automatiquement un rapport PDF des trajets de ce profil à la fréquence choisie.")
            }
            Section {
                vehicleSelectionRow(title: Text("Tous les véhicules"), isSelected: profile.vehicles.isEmpty) {
                    updateVehicles([])
                }
                ForEach(allVehicles) { vehicle in
                    vehicleSelectionRow(
                        title: Text(vehicle.name),
                        isSelected: profile.vehicles.contains { $0.persistentModelID == vehicle.persistentModelID }
                    ) {
                        toggleVehicle(vehicle)
                    }
                }
            } header: {
                Text("Véhicules")
            } footer: {
                Text("Seuls les trajets des véhicules sélectionnés seront inclus dans ce rapport.")
            }
            Section {
                Button("Supprimer ce profil", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
            }
        }
        // Le nom du profil est une donnée, pas du texte d'interface : seul le
        // titre de remplacement se traduit. Résolu ici plutôt que par
        // `navigationTitle("…")`, qui ne se relit pas au changement de langue.
        .navigationTitle(
            profile.name.isEmpty
                ? String(localized: "Profil", bundle: localizationBundle, locale: locale)
                : profile.name
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
        }
        .confirmationDialog(
            "Supprimer ce profil ?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { deleteProfile() }
            Button("Annuler", role: .cancel) {}
        }
    }

    /// Voir ReportExportView : le titre est un `Text` parce qu'un nom de
    /// véhicule ne se traduit pas, contrairement au libellé qui les couvre tous.
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
        var vehicles = profile.vehicles
        if let index = vehicles.firstIndex(where: { $0.persistentModelID == vehicle.persistentModelID }) {
            vehicles.remove(at: index)
        } else {
            vehicles.append(vehicle)
        }
        updateVehicles(vehicles)
    }

    private func updateName(_ name: String) {
        appServices.reportProfileService.updateName(name, for: profile, in: modelContext)
    }

    private func updatePeriodicity(_ periodicity: ReportPeriodicity) {
        appServices.reportProfileService.updatePeriodicity(periodicity, for: profile, in: modelContext)
        rescheduleNotification()
    }

    private func updateCustomInterval(_ days: Int) {
        appServices.reportProfileService.updateCustomInterval(days: days, for: profile, in: modelContext)
        rescheduleNotification()
    }

    private func updateCustomNextDueDate(_ date: Date) {
        appServices.reportProfileService.updateCustomNextDueDate(date, for: profile, in: modelContext)
        rescheduleNotification()
    }

    private func updateVehicles(_ vehicles: [Vehicle]) {
        appServices.reportProfileService.updateVehicles(vehicles, for: profile, in: modelContext)
    }

    private func rescheduleNotification() {
        if let nextDueDate = profile.nextDueDate {
            appServices.notificationService.scheduleReportReadyNotification(
                for: nextDueDate, profileID: profile.id, profileName: profile.name
            )
        } else {
            appServices.notificationService.cancelReportReadyNotification(profileID: profile.id)
        }
    }

    private func deleteProfile() {
        appServices.notificationService.cancelReportReadyNotification(profileID: profile.id)
        appServices.reportProfileService.deleteProfile(profile, in: modelContext)
        dismiss()
    }

    private func label(for periodicity: ReportPeriodicity) -> LocalizedStringKey {
        switch periodicity {
        case .none: return "Désactivé"
        case .monthly: return "Mensuel"
        case .quarterly: return "Trimestriel"
        case .yearly: return "Annuel"
        case .custom: return "Personnalisé"
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let profile = ReportProfile(name: "Exemple")
    container.mainContext.insert(profile)
    return NavigationStack {
        ReportProfileEditView(profile: profile)
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
