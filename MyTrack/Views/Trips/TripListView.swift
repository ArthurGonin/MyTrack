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

    private var trips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .confirmed }
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
                        }
                    }
                }
            }
            .appBackground()
            .localizedNavigationTitle("Trajets")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .accountToolbar()
        }
    }
}

struct TripRow: View {
    let trip: Trip
    let distanceUnit: DistanceUnit

    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(trip.startDate, style: .date)
                vehicleName
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(trip.formattedDistance(in: distanceUnit, locale: locale))
                Text(trip.formattedDuration(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
