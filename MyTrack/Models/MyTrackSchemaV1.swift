//
//  MyTrackSchemaV1.swift
//  MyTrack
//
//  La forme du magasin, figée telle qu'elle part sur l'App Store.
//
//  Un `VersionedSchema` ne fait rien à l'exécution : il donne un nom à une
//  forme. Celui-ci n'existe donc que pour être le point de départ nommé de la
//  première migration à venir — et c'est pour ça qu'il doit exister *avant* la
//  première publication, alors même qu'il ne sert encore à personne. Après,
//  il sera trop tard : les téléphones porteront un fichier à cette forme-ci
//  sans qu'aucun plan puisse dire « d'où l'on vient », et leurs trajets
//  n'auront aucun chemin vers la forme suivante.
//
//  Il pointe sur les modèles d'aujourd'hui plutôt que d'en porter des copies :
//  tant qu'il n'y a qu'une version, les deux décrivent la même forme, et
//  recopier cinq classes ici coûterait la convention « un type par fichier »
//  pour rien.
//
//  **Le jour où une V2 arrivera, ce raccourci tombe.** Les fichiers de
//  `Models/` décriront alors la V2, donc ce fichier-ci devra porter une copie
//  figée des classes telles qu'elles sont aujourd'hui, imbriquée dans l'enum,
//  et `models` pointer sur cette copie. Le travail est mécanique, mais il n'est
//  pas facultatif : sans lui, le plan de migration décrirait un départ et une
//  arrivée identiques, et ne migrerait rien.
//

import Foundation
import SwiftData

nonisolated enum MyTrackSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self]
    }
}
