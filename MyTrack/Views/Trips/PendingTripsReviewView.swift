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
    @Environment(AppServices.self) private var appServices

    // SwiftData's #Predicate macro can't compare an enum-typed property to a
    // case, so the pending-only filter is applied in Swift. Reading them
    // through @Query rather than a snapshot keeps this screen correct when the
    // same trip is confirmed from the notification while it's open.
    @Environment(\.locale) private var locale
    @Query(sort: \Trip.startDate, order: .forward) private var allTrips: [Trip]

    private var pendingTrips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .pendingConfirmation }
    }

    private let viewModel = PendingTripsReviewViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let trip = pendingTrips.first {
                    VStack(spacing: 16) {
                        Text(TripFormatting.dateAndTime(trip.startDate, locale: locale))
                            .foregroundStyle(.secondary)
                        Text(trip.formattedDistance(
                            in: appServices.unitSettingsService.distanceUnit, locale: locale
                        ))
                            .font(.largeTitle)
                        Text(trip.formattedDuration(locale: locale))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            Button("Non") {
                                viewModel.discard(trip, in: modelContext)
                            }
                            .buttonStyle(.bordered)

                            Button("Oui, enregistrer") {
                                viewModel.confirm(trip, in: modelContext)
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
            .localizedNavigationTitle("Trajets en attente")
        }
        .onChange(of: pendingTrips.isEmpty) { _, isEmpty in
            if isEmpty {
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
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
