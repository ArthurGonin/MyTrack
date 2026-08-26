//
//  PendingTripsReviewViewModel.swift
//  MyTrack
//
//  Stateless like the other list view models: the pending trips themselves are
//  read by the view through @Query, so the screen stays in step with the
//  notification's Yes/No actions, which resolve the very same trips against
//  SwiftData while this screen can be open.
//

import Foundation
import SwiftData

struct PendingTripsReviewViewModel {
    func confirm(_ trip: Trip, in context: ModelContext) {
        trip.confirmationStatus = .confirmed
        context.saveOrLog()
    }

    func discard(_ trip: Trip, in context: ModelContext) {
        trip.confirmationStatus = .deleted
        context.saveOrLog()
    }
}
