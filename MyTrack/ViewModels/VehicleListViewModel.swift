//
//  VehicleListViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct VehicleListViewModel {
    let vehicleService: VehicleService

    func addVehicle(_ draft: VehicleDraft, in context: ModelContext) {
        guard draft.isValid else { return }
        let vehicle = draft.makeVehicle()
        context.insert(vehicle)
        context.saveOrLog()

        // With nothing selected, every trip is recorded without a vehicle and
        // drops out of any report filtered by one — silently, since the app
        // only ever shows "Aucun véhicule". Deleting the last vehicle leaves
        // exactly that state (VehicleService.delete has no one left to
        // promote), so the next vehicle created has to take over.
        if vehicleService.selectedVehicle(in: context) == nil {
            vehicleService.select(vehicle, in: context)
        }
    }

    func deleteVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.delete(vehicle, in: context)
    }

    func selectVehicle(_ vehicle: Vehicle, in context: ModelContext) {
        vehicleService.select(vehicle, in: context)
    }
}
