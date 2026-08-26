# MyTrack

App iOS (SwiftUI) qui enregistre automatiquement les trajets en voiture : détection de conduite, tracking GPS, association à un véhicule, et confirmation manuelle des trajets détectés.

## Règles de travail (IMPORTANT)

- **Design toujours natif Apple, autant que possible.** Utiliser les composants et matériaux SwiftUI/UIKit standards plutôt que des styles custom — par exemple **Liquid Glass** pour les boutons et surfaces plutôt qu'un style maison, les contrôles système natifs (boutons, listes, navigation) plutôt que des équivalents recréés à la main.
- **Icônes = SF Symbols uniquement.** Quand on demande d'ajouter une icône, toujours utiliser un symbole SF Symbols (`Image(systemName:)`), jamais une image custom. Si l'utilisateur donne le nom exact du symbole, l'utiliser tel quel dans le code (`systemName: "nom.exact"`) sans le remplacer par autre chose.

## Stack

- Swift / SwiftUI, cible iOS.
- Persistance : **SwiftData** (`@Model`).
- Pas de SPM package ni de dépendances tierces — projet Xcode pur (`MyTrack.xcodeproj`).
- Pas de target de tests pour l'instant.

## Build / run

Le projet s'ouvre et se build via Xcode (`MyTrack.xcodeproj`). Pas de script CLI dédié — utiliser `xcodebuild` si besoin de build en ligne de commande, en pointant sur le scheme `MyTrack`.

## Architecture

Le code vit dans `MyTrack/`, organisé en couches classiques MVVM :

- **`Models/`** — entités SwiftData et types associés :
  - `Trip` (`@Model`) : trajet enregistré (dates, distance, coordonnées de départ/arrivée, points de route, véhicule associé, statut de confirmation).
  - `Vehicle`, `RoutePoint`, `TripSource` (origine du trajet : auto-détecté vs manuel), `TripConfirmationStatus`.
  - `Trip+Formatting.swift` : extensions de formatage d'affichage.
- **`Services/`** — logique métier et intégrations système, assemblées dans `AppServices` (composition root, injectée dans l'environnement SwiftUI depuis `MyTrackApp`) :
  - `LocationService` — accès GPS.
  - `MotionActivityService` — détection d'activité (marche/voiture) via CoreMotion.
  - `DrivingDetector` — combine motion + location pour détecter le début/fin de trajet en voiture.
  - `TripRecorder` — enregistre les points de route et persiste les `Trip` en base.
  - `VehicleService` — gestion des véhicules.
  - `NotificationService` — notifications locales (ex: demander confirmation d'un trajet détecté).
- **`ViewModels/`** — un ViewModel par écran principal (liste des trajets, revue des trajets en attente, enregistrement en cours, liste des véhicules).
- **`Views/`** — organisées par domaine : `Recording/`, `Trips/`, `Vehicles/`, plus `RootTabView` comme point d'entrée de la navigation par onglets.

`AppServices` est construit une seule fois dans `MyTrackApp.init()` avec le `ModelContext` partagé, pour que les écritures faites en arrière-plan (par `TripRecorder`/`DrivingDetector`) restent visibles des vues utilisant `@Query`.

## Conventions observées

- Un type par fichier, nommé comme le fichier.
- Les services sont des classes injectées via `@Observable` / `.environment(...)`, pas de singletons globaux.
- Les entités SwiftData restent simples (peu de logique) ; le formatage d'affichage est déporté dans des extensions dédiées (`Trip+Formatting.swift`) plutôt que dans le modèle lui-même.
