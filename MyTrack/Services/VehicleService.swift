//
//  VehicleService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class VehicleService {
    func selectedVehicle(in context: ModelContext) -> Vehicle? {
        let descriptor = FetchDescriptor<Vehicle>(predicate: #Predicate { $0.isSelected == true })
        return try? context.fetch(descriptor).first
    }

    func select(_ vehicle: Vehicle, in context: ModelContext) {
        let descriptor = FetchDescriptor<Vehicle>()
        guard let allVehicles = try? context.fetch(descriptor) else { return }
        for candidate in allVehicles {
            candidate.isSelected = candidate.persistentModelID == vehicle.persistentModelID
        }
        try? context.save()
    }
}
