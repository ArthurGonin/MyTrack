//
//  DeletedTripsViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct DeletedTripsViewModel {
    func restore(_ trip: Trip, in context: ModelContext) {
        trip.confirmationStatus = .confirmed
        context.saveOrLog()
    }

    func deletePermanently(_ trip: Trip, in context: ModelContext) {
        context.delete(trip)
        context.saveOrLog()
    }
}
