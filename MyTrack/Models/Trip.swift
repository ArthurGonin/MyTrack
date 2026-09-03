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

    /// Les trajets que celui-ci rassemble, quand il est né d'une fusion — vide
    /// pour tous les autres, ce qui est précisément ce qui les distingue
    /// (`isMerged`).
    ///
    /// La fusion n'écrase rien : chaque composant garde sa trace, sa distance
    /// et son coût, et le trajet fusionné n'est qu'un trajet de plus qui les
    /// représente. C'est ce qui permet de les revoir sur son écran de détail,
    /// et de les lui reprendre (voir `Trip+Merge`).
    ///
    /// `.cascade` : effacer définitivement un trajet fusionné emporte ses
    /// composants. Les laisser derrière (`.nullify`) les rendrait invisibles à
    /// jamais — ils ne sont plus `.confirmed`, donc plus dans aucune liste, et
    /// plus rattachés à rien qui puisse les y ramener.
    ///
    /// Optionnelle avec `[]` par défaut, comme `Vehicle.trips` : voir
    /// `Vehicle.storedEnergyType` pour ce que coûte une propriété
    /// non-optionnelle ajoutée à un modèle déjà en base.
    @Relationship(deleteRule: .cascade, inverse: \Trip.mergedInto)
    var mergedComponents: [Trip]? = []

    /// Le trajet fusionné dont celui-ci fait partie, s'il y en a un.
    var mergedInto: Trip?

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

    /// Vrai quand ce trajet est la fusion d'autres trajets.
    var isMerged: Bool { !(mergedComponents ?? []).isEmpty }

    /// Les composants dans l'ordre où ils ont été roulés. Une relation SwiftData
    /// ne promet aucun ordre : sans ce tri, la liste des trajets fusionnés et
    /// les drapeaux posés sur la carte se renuméroteraient d'un affichage à
    /// l'autre.
    var orderedComponents: [Trip] {
        (mergedComponents ?? []).sorted { $0.startDate < $1.startDate }
    }

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
