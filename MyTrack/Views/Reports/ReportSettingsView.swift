//
//  ReportSettingsView.swift
//  MyTrack
//
//  Reached from Account Settings: the list of periodic report profiles, each
//  with its own frequency and vehicle filter. Only the configuration lives
//  here — the reports these profiles produce show up in the Rapports tab,
//  alongside the manual exports.
//

import SwiftUI
import SwiftData

struct ReportSettingsView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @Query(sort: \ReportProfile.createdAt) private var profiles: [ReportProfile]
    @State private var newlyCreatedProfile: ReportProfile?

    var body: some View {
        Form {
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
            } footer: {
                Text("Génère automatiquement un rapport PDF par profil, à sa fréquence propre. Les rapports générés apparaissent dans l'onglet Rapports.")
            }
        }
        .localizedNavigationTitle("Rapports périodiques")
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
            ? String(localized: "Tous les véhicules", bundle: localizationBundle, locale: locale)
            : profile.vehicles.map(\.name).formatted(.list(type: .and).locale(locale))
        return "\(label(for: profile)) · \(vehiclesLabel)"
    }

    private func label(for profile: ReportProfile) -> String {
        switch profile.periodicity {
        case .none: return String(localized: "Désactivé", bundle: localizationBundle, locale: locale)
        case .monthly: return String(localized: "Mensuel", bundle: localizationBundle, locale: locale)
        case .quarterly: return String(localized: "Trimestriel", bundle: localizationBundle, locale: locale)
        case .yearly: return String(localized: "Annuel", bundle: localizationBundle, locale: locale)
        case .custom: return String(localized: "Tous les \(profile.customIntervalDays) jours", bundle: localizationBundle, locale: locale)
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
        // Traduit à la création : c'est ensuite une donnée que l'utilisateur
        // peut renommer, pas du texte d'interface — elle ne doit donc plus
        // bouger si la langue change après coup.
        let profile = appServices.reportProfileService.createProfile(
            name: String(localized: "Nouveau rapport périodique", bundle: localizationBundle, locale: locale),
            in: modelContext
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
