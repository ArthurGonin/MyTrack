//
//  TripListView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices

    // SwiftData's #Predicate macro doesn't support comparing enum-typed properties
    // directly (it can't build a key path to a plain enum case), so the confirmed-only
    // filter is applied in Swift instead of in the query.
    @Query(sort: \Trip.startDate, order: .reverse)
    private var allTrips: [Trip]

    /// L'ordre de tri choisi, gardé d'un lancement à l'autre : une liste rangée
    /// par coût ne doit pas se remettre d'elle-même dans l'ordre des dates
    /// pendant qu'on regarde ailleurs. `@AppStorage` plutôt qu'un service à
    /// part — comme la langue ou l'unité — parce que ce réglage-là ne concerne
    /// que cet écran et que personne d'autre n'a besoin de le lire.
    @AppStorage("tripSortOrder") private var sortOrder: TripSortOrder = .default

    private var trips: [Trip] {
        viewModel.sorted(
            allTrips.filter { $0.confirmationStatus == .confirmed }, by: sortOrder
        )
    }

    private var deletedTripsCount: Int {
        allTrips.filter { $0.confirmationStatus == .deleted }.count
    }

    private let viewModel = TripListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty && deletedTripsCount == 0 {
                    ContentUnavailableView(
                        "Aucun trajet",
                        systemImage: "map",
                        description: Text("Les trajets enregistrés apparaîtront ici.")
                    )
                } else {
                    List {
                        if !trips.isEmpty {
                            Section {
                                ForEach(trips) { trip in
                                    NavigationLink(value: trip) {
                                        TripRow(trip: trip, distanceUnit: appServices.unitSettingsService.distanceUnit)
                                    }
                                    .appCardRow()
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        viewModel.moveToTrash(trips[index], in: modelContext)
                                    }
                                }
                            }
                        }
                        Section {
                            NavigationLink {
                                DeletedTripsView()
                            } label: {
                                HStack {
                                    Label("Trajets supprimés", systemImage: "trash")
                                    Spacer()
                                    if deletedTripsCount > 0 {
                                        // `format:` plutôt qu'une interpolation :
                                        // le séparateur de milliers suit alors la
                                        // langue de l'app.
                                        Text(deletedTripsCount, format: .number)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .appCardRow()
                        }
                    }
                    // Les lignes portent elles-mêmes leur carte : le style de
                    // liste ne doit pas en dessiner une seconde autour d'elles.
                    .listStyle(.plain)
                    // Le tri se rejoue à chaque changement d'ordre : sans ça les
                    // lignes sautent d'un rang à l'autre sans transition.
                    .animation(.default, value: sortOrder)
                }
            }
            .appBackground()
            .localizedNavigationTitle("Trajets")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .toolbar {
                // Rien à trier tant qu'il n'y a pas de trajet : le bouton
                // n'apparaît qu'avec la liste.
                if !trips.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        sortMenu
                    }
                }
            }
            .accountToolbar()
        }
    }

    /// Le bouton de tri, en haut à droite. Le verre et la forme viennent de la
    /// barre elle-même — comme pour le « + » des rapports, il n'y a pas de
    /// `glassEffect` à poser à la main.
    private var sortMenu: some View {
        Menu {
            // Un `Picker` plutôt qu'une suite de boutons : c'est lui qui coche
            // l'ordre en cours, et son intitulé devient l'en-tête de la carte
            // qui s'ouvre. `inline` pour que les huit choix se posent
            // directement dans le menu, au lieu d'un sous-menu à rouvrir.
            Picker(selection: $sortOrder) {
                ForEach(TripSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            } label: {
                Text("Trier par")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Trier les trajets")
    }
}

struct TripRow: View {
    let trip: Trip
    let distanceUnit: DistanceUnit

    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startDate, style: .date)
                    .font(.subheadline.weight(.semibold))
                vehicleName
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.formattedDistance(in: distanceUnit, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                // Le coût se pose à côté de la durée plutôt que sur une
                // troisième ligne : la ligne reste haute de deux lignes, comme
                // celles des trajets dont on ne sait pas le coût.
                HStack(spacing: 4) {
                    Text(trip.formattedDuration(locale: locale))
                    if let cost = trip.formattedEnergyCost(locale: locale) {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(cost)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    /// Le nom d'un véhicule est une donnée saisie par l'utilisateur : il se
    /// rend tel quel, alors que le texte de remplacement, lui, se traduit.
    @ViewBuilder
    private var vehicleName: some View {
        if let name = trip.vehicle?.name {
            Text(name)
        } else {
            Text("Aucun véhicule")
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TripListView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
