//
//  DeletedTripsView.swift
//  MyTrack
//
//  Trips moved here by a swipe-to-delete on the main list, or by declining an
//  automatic trip (in-app or from the notification) instead of being erased
//  outright. From here they can be restored to the main list or purged for
//  good — mirroring the leading-swipe-to-restore / trailing-swipe-to-delete
//  pattern of Apple's own trash folders (Mail, Notes).
//

import SwiftUI
import SwiftData

struct DeletedTripsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices

    @Query(sort: \Trip.startDate, order: .reverse)
    private var allTrips: [Trip]

    private var deletedTrips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .deleted }
    }

    private let viewModel = DeletedTripsViewModel()

    var body: some View {
        Group {
            if deletedTrips.isEmpty {
                ContentUnavailableView(
                    "Aucun trajet supprimé",
                    systemImage: "trash",
                    description: Text("Les trajets supprimés apparaîtront ici.")
                )
            } else {
                List {
                    ForEach(deletedTrips) { trip in
                        NavigationLink(value: trip) {
                            TripRow(trip: trip, distanceUnit: appServices.unitSettingsService.distanceUnit)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                // `onDelete` anime le retrait de ligne (et la
                                // remontée des lignes suivantes) automatiquement ;
                                // un bouton de swipeActions "plain" ne le fait pas,
                                // il faut donc le demander explicitement pour
                                // retrouver la même animation que la suppression.
                                withAnimation {
                                    viewModel.restore(trip, in: modelContext)
                                }
                            } label: {
                                Label("Restaurer", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deletePermanently(trip, in: modelContext)
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                        .appCardRow()
                    }
                }
                // Les lignes portent elles-mêmes leur carte : le style de
                // liste ne doit pas en dessiner une seconde autour d'elles.
                .listStyle(.plain)
            }
        }
        .appBackground()
        .localizedNavigationTitle("Trajets supprimés")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let trip = Trip(startDate: .now.addingTimeInterval(-1800), source: .manual, vehicle: nil)
    trip.endDate = .now
    trip.distanceMeters = 8300
    trip.confirmationStatus = .deleted
    container.mainContext.insert(trip)
    return NavigationStack {
        DeletedTripsView()
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
