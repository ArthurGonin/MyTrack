//
//  TripListViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct TripListViewModel {
    /// Soft delete: the trip moves to "Trajets supprimés" instead of being
    /// erased outright, so it can still be restored or purged from there.
    func moveToTrash(_ trip: Trip, in context: ModelContext) {
        trip.confirmationStatus = .deleted
        context.saveOrLog()
    }
}
