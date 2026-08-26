//
//  AccountSettingsView.swift
//  MyTrack
//

import SwiftUI
import SwiftData
import UIKit

struct AccountSettingsView: View {
    /// Set when opened from a report-ready notification tap, so the view
    /// pushes straight to that report in the history instead of opening on
    /// the root settings screen.
    var openingReportID: UUID? = nil

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
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
            notificationService: appServices.notificationService
        )
    }

    var body: some View {
        @Bindable var unitSettings = appServices.unitSettingsService

        return NavigationStack(path: $path) {
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
                                if viewModel.enableAutoDetection() == .permissionDenied {
                                    isPermissionDeniedAlertPresented = true
                                }
                            } else {
                                viewModel.disableAutoDetection()
                            }
                        }
                    ))
                } footer: {
                    Text("Détecte automatiquement tes trajets en voiture.")
                }

                Section {
                    Picker("Distance", selection: $unitSettings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    // Two options don't warrant pushing a whole screen.
                    .pickerStyle(.menu)
                } header: {
                    Text("Unités")
                }

                Section {
                    NavigationLink("Rapport", value: SettingsRoute.report)
                }

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
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .report:
                    ReportSettingsView()
                case .reportHistory(let openingReportID):
                    ReportHistoryView(openingReportID: openingReportID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let openingReportID {
                    path = NavigationPath([SettingsRoute.report, SettingsRoute.reportHistory(openingReportID: openingReportID)])
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
