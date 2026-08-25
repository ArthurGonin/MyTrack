//
//  AccountSettingsView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct AccountSettingsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isPermissionDeniedAlertPresented = false
    @State private var reportSettings: ReportSettings?

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
                    if let reportSettings {
                        Picker("Fréquence des rapports", selection: Binding(
                            get: { reportSettings.periodicity },
                            set: { updatePeriodicity($0) }
                        )) {
                            ForEach(ReportPeriodicity.allCases, id: \.self) { periodicity in
                                Text(label(for: periodicity)).tag(periodicity)
                            }
                        }
                        if reportSettings.periodicity == .custom {
                            Stepper(
                                "Tous les \(reportSettings.customIntervalDays) jours",
                                value: Binding(
                                    get: { reportSettings.customIntervalDays },
                                    set: { updateCustomInterval($0) }
                                ),
                                in: 1...365
                            )
                        }
                    }
                    NavigationLink("Historique des rapports") {
                        ReportHistoryView()
                    }
                } footer: {
                    Text("Génère automatiquement un rapport PDF des trajets à la fréquence choisie.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .alert("Localisation refusée", isPresented: $isPermissionDeniedAlertPresented) {
                Button("Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Autorise l'accès à la position dans Réglages pour activer le suivi automatique.")
            }
            .onAppear {
                if reportSettings == nil {
                    reportSettings = appServices.reportSettingsService.currentSettings(in: modelContext)
                }
            }
        }
    }

    private func updatePeriodicity(_ periodicity: ReportPeriodicity) {
        let updated = appServices.reportSettingsService.updatePeriodicity(
            periodicity, customIntervalDays: nil, in: modelContext
        )
        reportSettings = updated
        rescheduleNotification(for: updated)
    }

    private func updateCustomInterval(_ days: Int) {
        let updated = appServices.reportSettingsService.updatePeriodicity(
            .custom, customIntervalDays: days, in: modelContext
        )
        reportSettings = updated
        rescheduleNotification(for: updated)
    }

    private func rescheduleNotification(for settings: ReportSettings) {
        if let nextDueDate = settings.nextDueDate {
            appServices.notificationService.scheduleReportReadyNotification(for: nextDueDate)
        } else {
            appServices.notificationService.cancelReportReadyNotification()
        }
    }

    private func label(for periodicity: ReportPeriodicity) -> String {
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
        for: Trip.self, Vehicle.self, UserProfile.self, ReportSettings.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return AccountSettingsView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
