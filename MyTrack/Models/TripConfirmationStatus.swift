//
//  TripConfirmationStatus.swift
//  MyTrack
//

import Foundation

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
