//
//  PendingTripsReviewView.swift
//  MyTrack
//
//  Presented on launch when automatic trips are still awaiting confirmation
//  (the notification was ignored, or the app was opened directly instead of
//  tapping a notification action). Reviews them oldest-first, one at a time.
//

import SwiftUI
import SwiftData

struct PendingTripsReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PendingTripsReviewViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let trip = viewModel?.currentTrip {
                    VStack(spacing: 16) {
                        Text(trip.startDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text(trip.formattedDistance)
                            .font(.largeTitle)
                        Text(trip.formattedDuration)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Button("Non") {
                                viewModel?.discardCurrent()
                            }
                            .buttonStyle(.bordered)

                            Button("Oui, enregistrer") {
                                viewModel?.confirmCurrent()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                } else {
                    Text("Tout est à jour")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Trajets en attente")
        }
        .onAppear {
            if viewModel == nil {
                viewModel = PendingTripsReviewViewModel(modelContext: modelContext)
            }
        }
        .onChange(of: viewModel?.pendingTrips.isEmpty) { _, isEmpty in
            if isEmpty == true {
                dismiss()
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let trip = Trip(startDate: .now.addingTimeInterval(-1800), source: .automatic, vehicle: nil)
    trip.endDate = .now
    trip.distanceMeters = 8300
    container.mainContext.insert(trip)
    return PendingTripsReviewView()
        .modelContainer(container)
}
