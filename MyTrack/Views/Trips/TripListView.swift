//
//  TripListView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext

    // SwiftData's #Predicate macro doesn't support comparing enum-typed properties
    // directly (it can't build a key path to a plain enum case), so the confirmed-only
    // filter is applied in Swift instead of in the query.
    @Query(sort: \Trip.startDate, order: .reverse)
    private var allTrips: [Trip]

    private var trips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .confirmed }
    }

    private let viewModel = TripListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "Aucun trajet",
                        systemImage: "map",
                        description: Text("Les trajets enregistrés apparaîtront ici.")
                    )
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteTrip(trips[index], in: modelContext)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trajets")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(trip.startDate, style: .date)
                Text(trip.vehicle?.name ?? "Aucun véhicule")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(trip.formattedDistance)
                Text(trip.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    TripListView()
        .modelContainer(for: [Trip.self, Vehicle.self], inMemory: true)
}
