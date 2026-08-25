//
//  TripListViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct TripListViewModel {
    func deleteTrip(_ trip: Trip, in context: ModelContext) {
        context.delete(trip)
        try? context.save()
    }
}
