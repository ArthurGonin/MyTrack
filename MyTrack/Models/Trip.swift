//
//  Trip.swift
//  MyTrack
//

import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var distanceMeters: Double
    var source: TripSource
    var confirmationStatus: TripConfirmationStatus
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var routePoints: [RoutePoint]
    var vehicle: Vehicle?

    var isActive: Bool { endDate == nil }

    init(startDate: Date, source: TripSource, vehicle: Vehicle?) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = nil
        self.distanceMeters = 0
        self.source = source
        self.confirmationStatus = source == .manual ? .confirmed : .pendingConfirmation
        self.routePoints = []
        self.vehicle = vehicle
    }
}
