//
//  PendingTripsReviewViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData
import Observation

@Observable
final class PendingTripsReviewViewModel {
    private let modelContext: ModelContext
    private(set) var pendingTrips: [Trip]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        let descriptor = FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate, order: .forward)])
        let allTrips = (try? modelContext.fetch(descriptor)) ?? []
        pendingTrips = allTrips.filter { $0.confirmationStatus == .pendingConfirmation }
    }

    var currentTrip: Trip? { pendingTrips.first }

    func confirmCurrent() {
        guard !pendingTrips.isEmpty else { return }
        let trip = pendingTrips.removeFirst()
        trip.confirmationStatus = .confirmed
        try? modelContext.save()
    }

    func discardCurrent() {
        guard !pendingTrips.isEmpty else { return }
        let trip = pendingTrips.removeFirst()
        modelContext.delete(trip)
        try? modelContext.save()
    }
}
