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

    /// L'énergie du véhicule, telle qu'elle est stockée. Se lit par
    /// `energyType`.
    ///
    /// Optionnelle, et non pas non-optionnelle avec une valeur par défaut : les
    /// deux compilent, mais la seconde plante à l'ouverture d'un magasin
    /// existant. SwiftData ajoute bien la colonne aux véhicules déjà
    /// enregistrés — c'est une migration légère, il n'y a rien à écrire pour ça
    /// — mais il la laisse vide, sans y reporter la valeur par défaut. La
    /// première lecture terminait alors sur « Could not cast value of type
    /// Swift.Optional<Any> to VehicleEnergyType », c'est-à-dire l'app qui se
    /// ferme au premier écran montrant un véhicule d'avant la mise à jour.
    private var storedEnergyType: VehicleEnergyType?

    /// La consommation moyenne, en L/100 km ou en kWh/100 km selon
    /// `energyType`. Nil tant qu'elle n'a pas été renseignée : le champ est
    /// facultatif, et zéro ne voudrait pas dire la même chose.
    var consumption: Double?

    /// Le prix d'un litre ou d'un kilowattheure, dans la devise de la région.
    var energyPrice: Double?

    /// La photo du véhicule, détourée et normalisée, telle qu'elle s'affiche sur
    /// l'accueil quand ce véhicule est choisi. Un PNG à fond transparent, au
    /// cadre que `VehiclePhotoNormalizer` impose à toutes.
    ///
    /// Optionnelle pour la raison dite plus haut sur `storedEnergyType` : une
    /// propriété ajoutée à un `@Model` déjà en base doit l'être, sans quoi la
    /// première lecture d'une ligne existante ferme l'app.
    ///
    /// `.externalStorage` la range dans un fichier à part plutôt que dans la
    /// base : un PNG d'un mégaoctet et demi n'a rien à faire au milieu de
    /// colonnes qu'on relit à chaque écran.
    @Attribute(.externalStorage) var photoData: Data?

    /// L'énergie du véhicule. Un véhicule enregistré avant que le champ existe
    /// n'en a aucune : il se lit thermique, la plus répandue, et l'écran de
    /// modification permet de le corriger.
    var energyType: VehicleEnergyType {
        get { storedEnergyType ?? .combustion }
        set { storedEnergyType = newValue }
    }

    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip]? = []

    @Relationship(inverse: \ReportProfile.vehicles)
    var reportProfiles: [ReportProfile]? = []

    init(
        name: String,
        licensePlate: String? = nil,
        isSelected: Bool = false,
        energyType: VehicleEnergyType = .combustion,
        consumption: Double? = nil,
        energyPrice: Double? = nil
    ) {
        self.name = name
        self.licensePlate = licensePlate
        self.isSelected = isSelected
        self.storedEnergyType = energyType
        self.consumption = consumption
        self.energyPrice = energyPrice
    }
}
