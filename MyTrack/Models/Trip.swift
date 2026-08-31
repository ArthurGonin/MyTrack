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

    /// Ce que valait le véhicule quand le trajet lui a été attaché : sa
    /// consommation, le prix de son énergie, et l'énergie elle-même. Figés ici
    /// plutôt que relus sur le véhicule, parce qu'un carburant plus cher le mois
    /// prochain ne doit pas réécrire ce qu'ont coûté les trajets déjà faits.
    ///
    /// Optionnels pour deux raisons : les trajets enregistrés avant que le coût
    /// existe n'en ont pas — `TripCostSnapshotService` s'en occupe — et une
    /// propriété ajoutée à un `@Model` doit l'être, sans quoi l'app plante sur
    /// les lignes déjà en base (voir `Vehicle.storedEnergyType`).
    ///
    /// Ils se lisent ensemble, jamais séparément : voir `Trip.energyFigures`.
    var recordedConsumption: Double?
    var recordedEnergyPrice: Double?
    var recordedEnergyType: VehicleEnergyType?

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
        // Même geste que `assignVehicle`, qu'un init ne peut pas encore appeler.
        self.recordedConsumption = vehicle?.consumption
        self.recordedEnergyPrice = vehicle?.energyPrice
        self.recordedEnergyType = vehicle?.energyType
    }
}
