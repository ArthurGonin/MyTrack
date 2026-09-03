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

    @State private var isDeleteConfirmationPresented = false
    @State private var isDeletionFailedAlertPresented = false
    @State private var isFeedbackPresented = false

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
            purchaseService: appServices.purchaseService
        )
    }

    var body: some View {
        @Bindable var unitSettings = appServices.unitSettingsService
        @Bindable var languageService = appServices.languageService
        @Bindable var drivingDetector = appServices.drivingDetector

        return NavigationStack {
            Form {
                // L'ordre suit ce que l'écran raconte : qui tu es, ce que
                // l'app fait pour toi, ce dont elle a besoin pour le faire, le
                // reste de ses fonctions, tes préférences, ce que tu paies,
                // puis la sortie.
                Section {
                    NavigationLink {
                        PersonalDataView()
                    } label: {
                        SettingsRowLabel(
                            "Données personnelles",
                            systemImage: "person.crop.square.fill",
                            tint: .indigo
                        )
                    }
                } header: {
                    Text("Compte")
                }

                Section {
                    // Pas d'alerte au refus : le pied de section juste dessous
                    // nomme déjà ce qui manque, et la section Autorisations qui
                    // suit porte la ligne qui le répare. Une modale par-dessus
                    // dirait la même chose en obligeant à s'en débarrasser
                    // avant de pouvoir agir.
                    Toggle(isOn: Binding(
                        get: { viewModel.isAutoDetectionEnabled },
                        set: { isOn in
                            if isOn {
                                Task { await viewModel.enableAutoDetection() }
                            } else {
                                viewModel.disableAutoDetection()
                            }
                        }
                    )) {
                        SettingsRowLabel(
                            "Suivi automatique",
                            systemImage: "bolt.square.fill",
                            tint: .green
                        )
                    }
                } header: {
                    Text("Enregistrement")
                } footer: {
                    Text(autoDetectionFooter)
                }

                // Sans en-tête : la section se rattache visuellement à celle
                // du dessus, dont elle précise le comportement. N'a de sens
                // que si le suivi automatique est actif — sans lui, aucun
                // trajet détecté ne viendrait jamais poser la question.
                if viewModel.isAutoDetectionEnabled {
                    Section {
                        Toggle(isOn: $drivingDetector.requiresTripConfirmation) {
                            SettingsRowLabel(
                                "Confirmer chaque trajet",
                                systemImage: "checkmark.square.fill",
                                tint: .teal
                            )
                        }
                    } footer: {
                        Text(tripConfirmationFooter)
                    }
                }

                // Juste sous le suivi automatique, parce que c'est ce dont il
                // dépend : quand son pied de section annonce « inactif, il
                // manque telle autorisation », ce qu'il faut faire est la ligne
                // d'en dessous. Le raccourci vers les Réglages d'iOS vivait
                // ici même, dans la section précédente ; il n'a plus lieu
                // d'être, chaque ligne portant désormais le sien.
                PermissionsSettingsSection()

                Section {
                    NavigationLink {
                        ReportSettingsView()
                    } label: {
                        SettingsRowLabel(
                            "Rapports périodiques",
                            systemImage: "square.text.square.fill",
                            tint: .orange
                        )
                    }
                } header: {
                    Text("Rapports")
                }

                Section {
                    // Style par défaut : six langues méritent l'écran poussé
                    // que SwiftUI ouvre tout seul dans un Form, là où deux
                    // unités tiennent dans un menu. Le changement s'applique
                    // aussitôt, sans redémarrage.
                    Picker(selection: $languageService.language) {
                        ForEach(AppLanguage.allCases) { language in
                            // Chaque langue s'annonce dans la sienne : ce
                            // libellé ne passe pas par le catalogue.
                            Text(language.nativeName).tag(language)
                        }
                    } label: {
                        SettingsRowLabel("Langue", systemImage: "character.square.fill", tint: .purple)
                    }

                    Picker(selection: $unitSettings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    } label: {
                        SettingsRowLabel("Distance", systemImage: "arrow.left.and.right.square.fill", tint: .brown)
                    }
                    // Two options don't warrant pushing a whole screen.
                    .pickerStyle(.menu)
                } header: {
                    Text("Langue et unités")
                }

                SubscriptionSettingsSection()

                Section {
                    // Au-dessus de l'avis, et c'est l'ordre qui compte : nous
                    // écrire d'abord, noter publiquement ensuite. Quelqu'un
                    // qu'une chose agace doit croiser le moyen de nous le dire
                    // avant celui de le dire à l'App Store.
                    Button {
                        isFeedbackPresented = true
                    } label: {
                        SettingsRowLabel(
                            "Envoyer un commentaire",
                            systemImage: "text.bubble.fill",
                            tint: .teal
                        )
                    }

                    Button {
                        if let appStoreReviewURL {
                            UIApplication.shared.open(appStoreReviewURL)
                        }
                    } label: {
                        SettingsRowLabel(
                            "Laisser un avis",
                            systemImage: "star.square.fill",
                            tint: .green
                        )
                    }
                    .disabled(appStoreReviewURL == nil)

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        SettingsRowLabel(
                            "Supprimer le compte",
                            systemImage: "trash.square.fill",
                            tint: .red
                        )
                    }
                } footer: {
                    Text("Supprime définitivement tous vos trajets, véhicules et réglages. Cette action est irréversible.")
                }
            }
            .appBackground()
            .localizedNavigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isFeedbackPresented) {
                FeedbackView()
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
                Text("Tous vos trajets, véhicules, rapports et réglages seront définitivement supprimés. Cette action est irréversible.")
            }
            .alert("Suppression incomplète", isPresented: $isDeletionFailedAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Vos données n'ont pas pu être entièrement supprimées. Réessayez.")
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
            return "Détecte automatiquement vos trajets en voiture."
        case .running:
            return "Vos trajets en voiture sont détectés automatiquement."
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

    private var tripConfirmationFooter: LocalizedStringKey {
        appServices.drivingDetector.requiresTripConfirmation
            ? "MyTrack vous demande de confirmer chaque trajet détecté avant de l'enregistrer."
            : "Les trajets détectés sont enregistrés automatiquement, sans confirmation."
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
