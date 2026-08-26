//
//  VehicleListViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct VehicleListViewModel {
    let vehicleService: VehicleService

    func addVehicle(name: String, licensePlate: String?, in context: ModelContext) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedPlate = licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicle = Vehicle(
            name: trimmedName,
            licensePlate: (trimmedPlate?.isEmpty ?? true) ? nil : trimmedPlate
        )
        context.insert(vehicle)
        context.saveOrLog()
    }

    func deleteVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.delete(vehicle, in: context)
    }

    func selectVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.select(vehicle, in: context)
    }
}
