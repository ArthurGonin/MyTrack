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
        try? context.save()
    }

    func deleteVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        context.delete(vehicle)
        try? context.save()
    }

    func selectVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.select(vehicle, in: context)
    }
}
