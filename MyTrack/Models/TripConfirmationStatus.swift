//
//  TripConfirmationStatus.swift
//  MyTrack
//

import Foundation

/// Ce type ne peut pas servir de filtre à SwiftData. Partout où l'app a besoin
/// d'un statut, elle charge la table entière et trie en Swift.
///
/// Mesuré le 6 septembre 2026, cinq trajets aux statuts connus posés en base.
/// Les deux façons d'écrire ce filtre échouent, et différemment :
///
/// - `#Predicate { $0.confirmationStatus == pending }` lève
///   `SwiftDataError.unsupportedPredicate` — « Captured/constant values of type
///   'TripConfirmationStatus' are not supported ». `fetch` et `fetchCount`
///   jettent tous les deux, et le message est parfaitement clair.
/// - `#Predicate { $0.confirmationStatus.rawValue == "pendingConfirmation" }`
///   **ferme l'app** : « Fatal error: Failed to validate
///   Trip.confirmationStatus.rawValue because rawValue is not a member of
///   TripConfirmationStatus », SwiftData/Schema.swift:346. Ce n'est pas une
///   erreur qu'on rattrape, c'est un `fatalError`.
///
/// Le danger n'est donc pas que SwiftData mente : c'est que
/// `(try? context.fetch(…)) ?? []`, le patron qu'emploie toute l'app, avale un
/// message pourtant explicite et rende un tableau vide. Un écran filtré ainsi
/// n'afficherait plus rien, sans une ligne dans les journaux pour le dire.
///
/// Le filtre en Swift est donc la voie, et non un pis-aller à reprendre : voir
/// `TripListView.confirmedTrips`, `PendingTripsReviewView.pendingTrips` et
/// `RootTabView.hasPendingTrips`. Sur une date, en revanche, `#Predicate`
/// fonctionne — `RootTabView.generateReport` s'en sert pour la période d'un
/// rapport.
enum TripConfirmationStatus: String, Codable {
    case pendingConfirmation
    case confirmed
    case deleted
    /// Le trajet a été fusionné avec d'autres : il existe toujours, avec sa
    /// trace, sa distance et son coût, mais c'est désormais le trajet fusionné
    /// qui le représente (voir `Trip+Merge`).
    ///
    /// Un statut à part plutôt qu'un `.confirmed` qu'on masquerait à
    /// l'affichage : les totaux du mois, les rapports et la liste ne retiennent
    /// que les trajets confirmés, et un composant compté à côté du trajet qui
    /// le contient doublerait la distance partout à la fois.
    case merged
}
