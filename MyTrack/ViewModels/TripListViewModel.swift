//
//  TripListViewModel.swift
//  MyTrack
//

import Foundation
import SwiftData

struct TripListViewModel {
    /// Soft delete: the trip moves to "Trajets supprimés" instead of being
    /// erased outright, so it can still be restored or purged from there.
    func moveToTrash(_ trip: Trip, in context: ModelContext) {
        trip.confirmationStatus = .deleted
        context.saveOrLog()
    }

    /// La liste rangée dans l'ordre demandé.
    ///
    /// En Swift et non dans le `@Query` : trois des quatre critères — le coût,
    /// la durée, et la date de fin qu'elle suppose — sont calculés à partir du
    /// trajet, pas stockés dessus, et `#Predicate` ne sait trier que sur des
    /// propriétés qui existent en base.
    func sorted(_ trips: [Trip], by order: TripSortOrder) -> [Trip] {
        // Un trajet en cours n'a pas encore de date de fin : sa durée se compte
        // jusqu'à maintenant, comme à l'affichage (`formattedDuration`). Cet
        // instant est pris une fois pour tout le tri, et non à chaque
        // comparaison : un comparateur qui ne répond pas toujours la même chose
        // donne un ordre qui dépend du chemin suivi pour l'obtenir.
        let now = Date()

        switch order {
        case .dateDescending:
            return sorted(trips, ascending: false) { $0.startDate }
        case .dateAscending:
            return sorted(trips, ascending: true) { $0.startDate }
        case .costAscending:
            return sortedByCost(trips, ascending: true)
        case .costDescending:
            return sortedByCost(trips, ascending: false)
        case .distanceAscending:
            return sorted(trips, ascending: true) { max(0, $0.distanceMeters) }
        case .distanceDescending:
            return sorted(trips, ascending: false) { max(0, $0.distanceMeters) }
        case .durationAscending:
            return sorted(trips, ascending: true) { duration(of: $0, now: now) }
        case .durationDescending:
            return sorted(trips, ascending: false) { duration(of: $0, now: now) }
        }
    }

    private func duration(of trip: Trip, now: Date) -> TimeInterval {
        (trip.endDate ?? now).timeIntervalSince(trip.startDate)
    }

    /// Le tri commun à tous les critères dont la valeur est toujours connue.
    ///
    /// `sorted(by:)` ne promet pas de laisser les ex æquo dans leur ordre
    /// d'origine : deux trajets de même distance pourraient donc changer de
    /// place d'un affichage à l'autre sans que rien n'ait bougé. D'où le
    /// départage par date, le plus récent d'abord — celui de la liste au repos.
    private func sorted<Value: Comparable>(
        _ trips: [Trip], ascending: Bool, by value: (Trip) -> Value
    ) -> [Trip] {
        trips.sorted { first, second in
            let firstValue = value(first)
            let secondValue = value(second)
            guard firstValue != secondValue else { return first.startDate > second.startDate }
            return ascending ? firstValue < secondValue : firstValue > secondValue
        }
    }

    /// Le tri par coût, à part parce que le coût peut manquer : un trajet fait
    /// avec un véhicule dont la consommation ou le prix de l'énergie n'est pas
    /// renseigné n'en a pas (voir `Trip+Cost`).
    ///
    /// Ces trajets-là se rangent en fin de liste dans les deux sens. Les placer
    /// avant le moins cher dans un sens et après le plus cher dans l'autre
    /// reviendrait à leur prêter un coût de zéro, puis un coût infini, alors
    /// qu'on n'en sait rien.
    private func sortedByCost(_ trips: [Trip], ascending: Bool) -> [Trip] {
        trips.sorted { first, second in
            switch (first.energyCost, second.energyCost) {
            case let (firstCost?, secondCost?) where firstCost != secondCost:
                return ascending ? firstCost < secondCost : firstCost > secondCost
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return first.startDate > second.startDate
            }
        }
    }
}
