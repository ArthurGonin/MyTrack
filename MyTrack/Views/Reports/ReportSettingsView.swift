//
//  ReportSettingsView.swift
//  MyTrack
//
//  Reached from Account Settings ("Rapport"): the history of already
//  generated reports, plus the list of periodic report profiles — each with
//  its own frequency and vehicle filter.
//

import SwiftUI
import SwiftData

struct ReportSettingsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReportProfile.createdAt) private var profiles: [ReportProfile]
    @State private var newlyCreatedProfile: ReportProfile?

    var body: some View {
        Form {
            Section {
                NavigationLink("Historique des rapports") {
                    ReportHistoryView()
                }
            }
            Section {
                if profiles.isEmpty {
                    ContentUnavailableView(
                        "Aucun rapport périodique",
                        systemImage: "doc.badge.clock",
                        description: Text("Configure un rapport périodique pour générer automatiquement un rapport PDF à intervalle régulier.")
                    )
                } else {
                    ForEach(profiles) { profile in
                        NavigationLink {
                            ReportProfileEditView(profile: profile)
                        } label: {
                            profileRow(profile)
                        }
                    }
                    .onDelete(perform: deleteProfiles)
                }
                Button {
                    addProfile()
                } label: {
                    Label("Configurer un nouveau rapport périodique", systemImage: "plus")
                }
            } header: {
                Text("Rapports périodiques")
            } footer: {
                Text("Génère automatiquement un rapport PDF par profil, à sa fréquence propre.")
            }
        }
        .navigationTitle("Rapport")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newlyCreatedProfile) { profile in
            ReportProfileEditView(profile: profile)
        }
    }

    private func profileRow(_ profile: ReportProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
            Text(summary(for: profile))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(for profile: ReportProfile) -> String {
        let vehiclesLabel = profile.vehicles.isEmpty
            ? "Tous les véhicules"
            : profile.vehicles.map(\.name).joined(separator: ", ")
        return "\(label(for: profile)) · \(vehiclesLabel)"
    }

    private func label(for profile: ReportProfile) -> String {
        switch profile.periodicity {
        case .none: return "Désactivé"
        case .monthly: return "Mensuel"
        case .quarterly: return "Trimestriel"
        case .yearly: return "Annuel"
        case .custom: return "Tous les \(profile.customIntervalDays) jours"
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            let profile = profiles[index]
            appServices.notificationService.cancelReportReadyNotification(profileID: profile.id)
            appServices.reportProfileService.deleteProfile(profile, in: modelContext)
        }
    }

    private func addProfile() {
        let profile = appServices.reportProfileService.createProfile(
            name: "Nouveau rapport périodique", in: modelContext
        )
        newlyCreatedProfile = profile
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return NavigationStack {
        ReportSettingsView()
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
