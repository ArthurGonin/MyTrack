//
//  ReportProfileEditView.swift
//  MyTrack
//
//  Edits one periodic report profile: its name, frequency, and which
//  vehicles it covers. Every control saves immediately through
//  ReportProfileService, same live-edit pattern the rest of the app uses.
//
//  Le champ du nom est la seule exception, et pour une raison de coût : il se
//  frappe caractère par caractère, là où une fréquence se choisit d'un geste.
//  Écrire dans le profil à chaque touche ne coûte rien — c'est ce qui garde le
//  live-edit —, mais l'écriture sur le disque et la replanification de la
//  notification, elles, n'ont pas à se rejouer douze fois pour un nom de douze
//  lettres : la seconde repasse par le centre de notifications du système à
//  chaque fois. Les deux attendent donc que la saisie soit finie — le champ
//  perd le focus, ou l'écran s'en va.
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

    /// Vrai dès que « Supprimer ce profil » a été touché.
    ///
    /// Même précaution que dans `TripDetailView` : la suppression efface le
    /// profil que cet écran montre, mais l'écran met le temps d'une animation à
    /// se retirer — et SwiftUI le redessine pendant ce temps-là. Relire alors la
    /// moindre propriété d'un profil effacé ferme l'app (« This model instance
    /// was invalidated because its backing data could no longer be found in the
    /// store »). Le corps se vide donc d'un coup, et ce qui glisse hors de
    /// l'écran est le fond gris de l'app.
    @State private var isDeleted = false

    /// Le focus du champ du nom : sa retombée est ce qui déclenche l'écriture.
    @FocusState private var isNameFocused: Bool

    /// Vrai quand le nom a changé depuis la dernière écriture. Évite d'écrire
    /// et de replanifier en quittant un écran qu'on n'a fait que regarder.
    @State private var hasUnsavedName = false

    var body: some View {
        Group {
            if isDeleted {
                Color.clear
            } else {
                form
            }
        }
        .appBackground()
        // Le focus ne retombe pas toujours avant que l'écran s'en aille — un
        // retour par le bord emporte les deux ensemble. Sans ça, le dernier nom
        // frappé restait en mémoire jusqu'à la sauvegarde automatique de
        // SwiftData, et la notification gardait l'ancien.
        .onDisappear { commitName() }
        .confirmationDialog(
            "Supprimer ce profil ?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) { deleteProfile() }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Nom du profil", text: Binding(
                    get: { profile.name },
                    set: { typeName($0) }
                ))
                .focused($isNameFocused)
                .onChange(of: isNameFocused) { _, isFocused in
                    if !isFocused { commitName() }
                }
            }
            Section {
                Picker("Fréquence", selection: Binding(
                    get: { profile.periodicity },
                    set: { updatePeriodicity($0) }
                )) {
                    ForEach(ReportPeriodicity.allCases, id: \.self) { periodicity in
                        Text(periodicity.label).tag(periodicity)
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

    /// Le rappel déjà programmé porte le nom du profil dans son texte : sans
    /// cette reprogrammation, « Le rapport "Nouveau rapport périodique" est
    /// prêt » arrivait des semaines après que l'utilisateur l'a renommé.
    /// Une touche : le profil change tout de suite, en mémoire seulement. Ce
    /// qui coûte attend `commitName`.
    private func typeName(_ name: String) {
        profile.name = name
        hasUnsavedName = true
    }

    /// La saisie est finie : on écrit, et on refait la notification — dont le
    /// texte porte le nom du profil, d'où la replanification.
    ///
    /// Le garde sur `isDeleted` n'est pas de la précaution : supprimer le
    /// profil retire l'écran, donc fait retomber le focus, donc passerait ici —
    /// à lire un profil que l'on vient d'effacer. Voir `isDeleted`.
    private func commitName() {
        guard !isDeleted, hasUnsavedName else { return }
        hasUnsavedName = false
        appServices.reportProfileService.updateName(profile.name, for: profile, in: modelContext)
        rescheduleNotification()
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

    /// Sans garde sur la périodicité : `scheduleReportReadyNotifications`
    /// annule de lui-même quand le profil n'a plus d'échéance, ce qui est le
    /// cas dès qu'on le désactive.
    private func rescheduleNotification() {
        appServices.notificationService.scheduleReportReadyNotifications(for: profile)
    }

    /// Dans cet ordre, et pas un autre : le corps cesse de lire le profil,
    /// l'écran se retire, et le profil s'efface enfin — voir `isDeleted`.
    private func deleteProfile() {
        let profileID = profile.id
        isDeleted = true
        dismiss()
        appServices.notificationService.cancelReportReadyNotification(profileID: profileID)
        appServices.reportProfileService.deleteProfile(profile, in: modelContext)
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
