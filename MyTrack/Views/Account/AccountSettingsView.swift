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

    // TODO: remplacer par l'App Store ID réel une fois l'app publiée sur App Store Connect.
    private let appStoreID = "TODO_APP_STORE_ID"

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
        NavigationStack {
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
                    NavigationLink("Rapport") {
                        ReportSettingsView()
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Laisser un avis", systemImage: "star.bubble")
                    }

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
            .confirmationDialog(
                "Supprimer le compte ?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    deleteAccount()
                }

                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Tous tes trajets, véhicules et réglages seront supprimés définitivement.")
            }
        }
    }

    private func deleteAccount() {
        appServices.eraseAllData(in: modelContext)
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
