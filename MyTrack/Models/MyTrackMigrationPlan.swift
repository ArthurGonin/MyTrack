//
//  MyTrackMigrationPlan.swift
//  MyTrack
//
//  Comment le magasin d'une version passe à la forme de la suivante.
//
//  SwiftData compare à chaque ouverture la forme que le code demande à celle
//  que le fichier a sur le disque. Il comble seul les écarts évidents — une
//  propriété optionnelle ajoutée, une propriété retirée, un modèle nouveau :
//  c'est la migration légère, et elle n'a besoin de personne. Les autres, il
//  refuse de les deviner : renommer une propriété, changer son type, la rendre
//  obligatoire, déplacer une donnée d'un modèle à l'autre. Devant l'un de
//  ceux-là sans instructions, il n'ouvre pas le fichier du tout.
//
//  Ce plan est l'endroit où ces instructions s'écrivent. Il est vide pour
//  l'instant, et c'est normal : une seule version publiée, donc rien à
//  traverser. Il n'en est pas inutile pour autant — il déclare `MyTrackSchemaV1`,
//  et c'est cette déclaration-là qui rend la suite possible.
//
//  **Ce qu'il faudra faire pour une V2 :** figer la forme actuelle dans
//  `MyTrackSchemaV1` (voir son en-tête), écrire un `MyTrackSchemaV2` décrivant
//  la nouvelle, ajouter les deux à `schemas` dans l'ordre, pointer `current`
//  sur la V2, et poser l'étape entre elles dans `stages` :
//
//  ```swift
//  static var stages: [MigrationStage] {
//      [.custom(
//          fromVersion: MyTrackSchemaV1.self,
//          toVersion: MyTrackSchemaV2.self,
//          willMigrate: { context in /* lire l'ancienne forme, la mettre de côté */ },
//          didMigrate: { context in /* la réécrire dans la nouvelle */ }
//      )]
//  }
//  ```
//
//  `.lightweight(fromVersion:toVersion:)` suffit quand l'écart est de ceux que
//  SwiftData sait combler : l'étape ne sert alors qu'à nommer le passage.
//

import Foundation
import SwiftData

nonisolated enum MyTrackMigrationPlan: SchemaMigrationPlan {
    /// Les versions publiées, de la plus ancienne à la plus récente. L'ordre
    /// est ce qui trace le chemin : un magasin en V1 traverse chaque étape
    /// jusqu'à la dernière, il ne saute pas.
    static var schemas: [any VersionedSchema.Type] { [MyTrackSchemaV1.self] }

    /// Les passages d'une version à la suivante. Vide tant qu'il n'y en a
    /// qu'une.
    static var stages: [MigrationStage] { [] }

    /// La version que le code décrit aujourd'hui — toujours la dernière de
    /// `schemas`.
    ///
    /// Nommée ici pour que `MyTrackApp` construise son `Schema` à partir d'elle
    /// plutôt que de recopier la liste des modèles à côté. Deux listes de
    /// modèles finissent toujours par diverger, et celle qui en oublie un le
    /// fait disparaître du magasin sans un mot : les lignes restent sur le
    /// disque, mais plus rien ne sait les lire.
    static var current: any VersionedSchema.Type { MyTrackSchemaV1.self }
}
