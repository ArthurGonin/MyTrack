//
//  Trip+Cost.swift
//  MyTrack
//
//  Ce qu'un trajet a coûté en énergie, déduit de la distance parcourue et de ce
//  que valait le véhicule à ce moment-là : sa consommation moyenne et le prix de
//  son plein.
//
//  C'est une estimation, et elle le reste : personne ne relève le compteur à
//  chaque trajet. D'où le calcul plutôt qu'un champ de plus à saisir — et d'où
//  le `nil` partout où une des deux valeurs manque, parce qu'un coût sans
//  consommation renseignée serait un chiffre inventé.
//

import Foundation

extension Trip {
    /// Les trois chiffres dont le coût dépend, pris ensemble.
    ///
    /// Ensemble, et jamais un à un : croiser une consommation figée l'an dernier
    /// avec le prix du carburant d'aujourd'hui donnerait un coût que le trajet
    /// n'a jamais eu.
    struct EnergyFigures: Equatable {
        let consumption: Double
        /// Nil quand le prix n'était pas renseigné : le trajet a alors une
        /// consommation, mais pas de coût.
        let price: Double?
        let energyType: VehicleEnergyType
    }

    /// Les chiffres retenus pour ce trajet.
    ///
    /// Ceux figés au moment où le véhicule lui a été attaché, s'il en a — c'est
    /// le cas de tout trajet enregistré depuis que le coût existe. Sinon ceux du
    /// véhicule aujourd'hui : un trajet plus ancien n'a aucun chiffre d'époque à
    /// faire valoir, et le dernier prix connu vaut mieux que rien en attendant
    /// que `TripCostSnapshotService` le lui fige.
    var energyFigures: EnergyFigures? {
        // Un trajet fusionné n'a pas de chiffres à lui : il montre ceux de ses
        // composants quand ils s'accordent, et rien du tout quand ils divergent.
        // Deux trajets faits à des prix du litre différents n'ont pas de prix
        // commun à annoncer, et en choisir un ferait passer l'autre à la trappe.
        if isMerged { return sharedComponentFigures }
        if let recordedConsumption {
            return EnergyFigures(
                consumption: recordedConsumption,
                price: recordedEnergyPrice,
                // Le type n'a pas toujours suivi la consommation dans les
                // premières versions : le véhicule sert alors de recours, et le
                // thermique de dernier mot — c'est ce que vaut un véhicule dont
                // l'énergie n'a jamais été précisée.
                energyType: recordedEnergyType ?? vehicle?.energyType ?? .combustion
            )
        }
        guard let vehicle, let consumption = vehicle.consumption else { return nil }
        return EnergyFigures(
            consumption: consumption, price: vehicle.energyPrice, energyType: vehicle.energyType
        )
    }

    /// L'énergie dépensée : des litres pour un thermique ou un hybride, des
    /// kilowattheures pour un électrique.
    ///
    /// La distance est ramenée à zéro au minimum, comme dans
    /// `TripFormatting.distance` : une distance négative est un enregistrement
    /// abîmé, pas un trajet qui rend du carburant.
    var energyUsed: Double? {
        if isMerged { return componentsTotal { $0.energyUsed } }
        guard let figures = energyFigures, figures.consumption > 0 else { return nil }
        let kilometers = max(0, distanceMeters) / 1000
        return kilometers / 100 * figures.consumption
    }

    /// Ce que cette énergie a coûté, dans la devise de la région.
    var energyCost: Double? {
        // La somme de ce qu'ont coûté les composants, et non la distance totale
        // repassée par la formule : dès que deux d'entre eux n'ont pas été faits
        // au même prix, les deux chiffres diffèrent — et celui-là contredirait
        // la liste des trajets fusionnés, juste en dessous, où chacun montre le
        // sien.
        if isMerged { return componentsTotal { $0.energyCost } }
        guard let energyUsed, let price = energyFigures?.price, price > 0 else { return nil }
        return energyUsed * price
    }

    /// Les chiffres des composants quand ils sont les mêmes pour tous, nil
    /// sinon — y compris quand un seul composant n'en a pas.
    private var sharedComponentFigures: EnergyFigures? {
        let components = orderedComponents
        let figures = components.compactMap(\.energyFigures)
        guard figures.count == components.count, let first = figures.first else { return nil }
        return figures.allSatisfy { $0 == first } ? first : nil
    }

    /// Le total d'une valeur sur les composants, ou nil dès qu'un seul ne l'a
    /// pas : un total auquel il manque un trajet se lit comme un total complet.
    private func componentsTotal(_ value: (Trip) -> Double?) -> Double? {
        let components = orderedComponents
        let values = components.compactMap(value)
        guard values.count == components.count, !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// Attache un véhicule au trajet et fige ses chiffres du moment.
    ///
    /// Tout changement de véhicule passe par là : réattribuer un trajet à une
    /// autre voiture doit lui donner les chiffres de celle-là, sinon le coût
    /// affiché serait celui d'un véhicule et le nom celui d'un autre.
    ///
    /// Un trajet fusionné passe la consigne à ses composants : c'est d'eux que
    /// vient son coût, et les laisser sur l'ancienne voiture donnerait un trajet
    /// qui porte un nom et une addition qui ne vont pas ensemble.
    func assignVehicle(_ vehicle: Vehicle?) {
        self.vehicle = vehicle
        recordedConsumption = vehicle?.consumption
        recordedEnergyPrice = vehicle?.energyPrice
        recordedEnergyType = vehicle?.energyType
        for component in orderedComponents {
            component.assignVehicle(vehicle)
        }
    }
}
