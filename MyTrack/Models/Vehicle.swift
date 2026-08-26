//
//  Vehicle.swift
//  MyTrack
//

import Foundation
import SwiftData

@Model
final class Vehicle {
    var name: String
    var licensePlate: String?
    var isSelected: Bool

    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip]? = []

    @Relationship(inverse: \ReportProfile.vehicles)
    var reportProfiles: [ReportProfile]? = []

    init(name: String, licensePlate: String? = nil, isSelected: Bool = false) {
        self.name = name
        self.licensePlate = licensePlate
        self.isSelected = isSelected
    }
}
