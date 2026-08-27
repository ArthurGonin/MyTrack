//
//  AccountSettingsView.swift
//  MyTrack
//

import SwiftUI
import SwiftData
import UIKit

struct AccountSettingsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isPermissionDeniedAlertPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletionFailedAlertPresented = false

    // TODO: renseigner l'App Store ID réel une fois l'app publiée sur App Store
    // Connect. Tant qu'il vaut nil, la ligne « Laisser un avis » reste
    // désactivée plutôt que d'ouvrir un lien mort.
    private let appStoreID: String? = nil

    private var appStoreReviewURL: URL? {
        guard let appStoreID else { return nil }
        return URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
    }

    private var viewModel: RecordTripViewModel {
        RecordTripViewModel(
            tripRecorder: appServices.tripRecorder,
            locationService: appServices.locationService,
            vehicleService: appServices.vehicleService,
            drivingDetector: appServices.drivingDetector,
            notificationService: appServices.notificationService,
            motionActivityService: appServices.motionActivityService,
            purchaseService: appServices.purchaseService
        )
    }

    var body: some View {
        @Bindable var unitSettings = appServices.unitSettingsService
        @Bindable var languageService = appServices.languageService

        return NavigationStack {
            Form {
                Section {
                    NavigationLink("Données personnelles") {
                        PersonalDataView()
                    }
                }

                Section {
                    Toggle("Suivi automatique", isOn: Binding(
                        get: { viewModel.isAutoDetectionEnabled },
                        set: { isOn in
                            if isOn {
                                Task {
                                    if await viewModel.enableAutoDetection() == .permissionDenied {
                                        isPermissionDeniedAlertPresented = true
                                    }
                                }
                            } else {
                                viewModel.disableAutoDetection()
                            }
                        }
                    ))

                    if isAutoDetectionBlockedByPermission {
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } footer: {
                    Text(autoDetectionFooter)
                }

                Section {
                    // Style par défaut : six langues méritent l'écran poussé
                    // que SwiftUI ouvre tout seul dans un Form, là où deux
                    // unités tiennent dans un menu. Le changement s'applique
                    // aussitôt, sans redémarrage.
                    Picker("Langue", selection: $languageService.language) {
                        ForEach(AppLanguage.allCases) { language in
                            // Chaque langue s'annonce dans la sienne : ce
                            // libellé ne passe pas par le catalogue.
                            Text(language.nativeName).tag(language)
                        }
                    }

                    Picker("Distance", selection: $unitSettings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    // Two options don't warrant pushing a whole screen.
                    .pickerStyle(.menu)
                } header: {
                    Text("Langue et unités")
                }

                Section {
                    NavigationLink("Rapports périodiques") {
                        ReportSettingsView()
                    }
                }

                SubscriptionSettingsSection()

                Section {
                    Button {
                        if let appStoreReviewURL {
                            UIApplication.shared.open(appStoreReviewURL)
                        }
                    } label: {
                        Label("Laisser un avis", systemImage: "star.bubble")
                    }
                    .disabled(appStoreReviewURL == nil)

                    Button("Supprimer le compte", role: .destructive) {
                        isDeleteConfirmationPresented = true
                    }
                } footer: {
                    Text("Supprime définitivement tous tes trajets, véhicules et réglages. Cette action est irréversible.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Localisation refusée",
                isPresented: $isPermissionDeniedAlertPresented
            ) {
                Button("Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }

                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Autorise l'accès à la position dans Réglages pour activer le suivi automatique.")
            }
            .alert(
                "Supprimer le compte ?",
                isPresented: $isDeleteConfirmationPresented
            ) {
                Button("Supprimer", role: .destructive) {
                    deleteAccount()
                }

                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous tes trajets, véhicules, rapports et réglages seront définitivement supprimés. Cette action est irréversible.")
            }
            .alert("Suppression incomplète", isPresented: $isDeletionFailedAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Tes données n'ont pas pu être entièrement supprimées. Réessaie.")
            }
        }
    }

    /// The toggle records what the user asked for; this says what is actually
    /// happening. Without it the setting could sit there reading "on" while
    /// monitoring refused to arm for want of a permission — and no trip would
    /// ever be detected.
    private var autoDetectionFooter: LocalizedStringKey {
        switch appServices.drivingDetector.status {
        case .off:
            return "Détecte automatiquement tes trajets en voiture."
        case .running:
            return "Tes trajets en voiture sont détectés automatiquement."
        case .needsAlwaysLocation:
            return "Inactif : le suivi automatique a besoin de l'accès à la position réglé sur « Toujours » pour que l'app soit réveillée au début d'un trajet."
        case .needsMotionAccess:
            return "Inactif : le suivi automatique a besoin de l'accès à Motion et forme pour reconnaître la conduite."
        case .unsupportedDevice:
            return "Cet appareil ne mesure pas l'activité de mouvement : le suivi automatique ne peut pas fonctionner ici."
        case .needsSubscription:
            return "Inactif : l'enregistrement de nouveaux trajets nécessite un abonnement actif."
        }
    }

    /// Only the two permission cases are worth a shortcut — an unsupported
    /// device has nothing to grant.
    private var isAutoDetectionBlockedByPermission: Bool {
        switch appServices.drivingDetector.status {
        case .needsAlwaysLocation, .needsMotionAccess: return true
        // L'abonnement ne se règle pas dans les Réglages iOS : la section
        // Abonnement juste en dessous porte déjà le bon bouton.
        case .off, .running, .unsupportedDevice, .needsSubscription: return false
        }
    }

    private func deleteAccount() {
        // Only report success once the deletion actually reached the store:
        // otherwise everything would come back at the next launch, after the
        // user was told their account was gone.
        guard appServices.eraseAllData(in: modelContext) else {
            isDeletionFailedAlertPresented = true
            return
        }
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return AccountSettingsView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
