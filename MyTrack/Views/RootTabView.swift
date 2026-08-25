//
//  RootTabView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isPendingReviewPresented = false

    var body: some View {
        TabView {
            RecordTripView()
                .tabItem {
                    Label("Enregistrer", systemImage: "record.circle")
                }
            TripListView()
                .tabItem {
                    Label("Trajets", systemImage: "list.bullet")
                }
        }
        .onAppear {
            let descriptor = FetchDescriptor<Trip>()
            let hasPendingTrips = ((try? modelContext.fetch(descriptor)) ?? [])
                .contains { $0.confirmationStatus == .pendingConfirmation }
            if hasPendingTrips {
                isPendingReviewPresented = true
            }
        }
        .sheet(isPresented: $isPendingReviewPresented) {
            PendingTripsReviewView()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
