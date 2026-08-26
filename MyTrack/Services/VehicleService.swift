//
//  VehicleService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class VehicleService {
    func allVehicles(in context: ModelContext) -> [Vehicle] {
        let descriptor = FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func selectedVehicle(in context: ModelContext) -> Vehicle? {
        var descriptor = FetchDescriptor<Vehicle>(predicate: #Predicate { $0.isSelected == true })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func select(_ vehicle: Vehicle, in context: ModelContext) {
        for candidate in allVehicles(in: context) {
            candidate.isSelected = candidate.persistentModelID == vehicle.persistentModelID
        }
        context.saveOrLog()
    }

    /// Deletes a vehicle and, when it was the selected one, promotes another so
    /// the next trip is still attributed to something. Without this the app is
    /// left silently in the "Aucun véhicule" state after deleting the vehicle
    /// the user was actually using.
    func delete(_ vehicle: Vehicle, in context: ModelContext) {
        let wasSelected = vehicle.isSelected
        context.delete(vehicle)
        context.saveOrLog()

        guard wasSelected, let replacement = allVehicles(in: context).first else { return }
        select(replacement, in: context)
    }
}
