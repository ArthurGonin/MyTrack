# MyTrack

App iOS (SwiftUI) qui enregistre les trajets en voiture : détection automatique de conduite,
tracking GPS, association à un véhicule, estimation du coût en énergie, et rapports PDF —
ponctuels ou périodiques. L'app entière est payante (abonnement ou achat unique).

## Règles de travail (IMPORTANT)

- **Design toujours natif Apple, autant que possible.** Utiliser les composants et matériaux
  SwiftUI/UIKit standards plutôt que des styles custom — par exemple **Liquid Glass** pour les
  boutons et surfaces plutôt qu'un style maison, les contrôles système natifs (boutons, listes,
  navigation) plutôt que des équivalents recréés à la main.
- **Icônes = SF Symbols uniquement.** Quand on demande d'ajouter une icône, toujours utiliser un
  symbole SF Symbols (`Image(systemName:)`), jamais une image custom. Si l'utilisateur donne le
  nom exact du symbole, l'utiliser tel quel dans le code (`systemName: "nom.exact"`) sans le
  remplacer par autre chose.
- **Une nouvelle propriété dans un `@Model` doit être optionnelle.** SwiftData ajoute bien la
  colonne aux lignes existantes, mais il la laisse vide sans y reporter la valeur par défaut : une
  propriété non-optionnelle compile et ferme l'app au premier écran qui lit une ligne d'avant la
  mise à jour. Voir `Vehicle.storedEnergyType`, qui porte l'explication complète.
- **Ne pas laisser un corps de vue lire un modèle qu'on vient de supprimer.** `dismiss()` retire
  l'écran avec une animation, et SwiftUI le redessine pendant ce temps : lire une propriété d'un
  `@Model` effacé ferme l'app. Le patron est dans `TripDetailView.isSeparated` et
  `ReportProfileEditView.isDeleted` — vider le corps, fermer, puis supprimer.
- **Le texte affiché passe par le catalogue de chaînes**, en six langues. Hors SwiftUI (PDF,
  notifications), utiliser `String(localized:bundle:locale:)` avec le bundle *et* la locale de
  `LanguageService` : `String(localized:)` seul retombe sur la langue du système.

## Stack

- Swift / SwiftUI, cible iOS 26.0. Pas de SPM, pas de dépendance tierce — projet Xcode pur
  (`MyTrack.xcodeproj`), avec des groupes synchronisés sur le système de fichiers : un fichier
  ajouté dans `MyTrack/` entre dans la cible sans toucher au `.pbxproj`.
- Persistance : **SwiftData** (`@Model`), à travers `MyTrackMigrationPlan`. `MyTrackSchemaV1`
  fige la V1.0.0 et porte la liste des modèles — c'est elle qui fait autorité, pas une seconde
  liste posée ailleurs. Une fois l'app publiée, tout changement de modèle demandera une V2 et
  une `MigrationStage`.
- Concurrence : `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` et
  `SWIFT_STRICT_CONCURRENCY = complete`, en mode langage Swift 5. Tout est donc sur le fil
  principal par défaut ; ce qui n'y est pas le dit (`nonisolated`). **Le projet compile sans un
  seul avertissement**, et c'est à garder ainsi. Attention : l'`xcodebuild` incrémental n'en
  émet aucun pour un fichier qu'il ne recompile pas, donc un build vert ne prouve rien sur le
  reste — `touch` le fichier suspect pour savoir. Un objet mené par un cadre système hors du fil
  principal (une session AVFoundation, le centre de notifications) porte `nonisolated` sur sa
  propriété : c'est la description de ce qui se passe, pas une échappatoire.
- Achats : StoreKit 2, avec `MyTrack.storekit` pour les essais depuis Xcode (le simulateur en
  ligne de commande ne sait pas appliquer cette configuration).
- Pas de cible de tests.

## Build / run

Le projet s'ouvre et se build via Xcode. En ligne de commande, `xcode-select` pointe sur les
Command Line Tools : il faut donc préfixer explicitement.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project MyTrack.xcodeproj -scheme MyTrack \
  -destination 'generic/platform=iOS Simulator' build
```

L'incrémental saute parfois des modifications sans le dire : si un changement ne se voit pas dans
le simulateur, suspecter le build avant le code et refaire un `clean build`.

## Architecture

Le code vit dans `MyTrack/`, en couches MVVM. `Server/` porte deux Workers Cloudflare.

- **`Models/`** — entités SwiftData et types de valeur :
  - `Trip` (dates, distance, coordonnées, points de route, véhicule, statut de confirmation,
    chiffres d'énergie figés, composants de fusion), `Vehicle`, `UserProfile`, `ReportProfile`,
    `GeneratedReport`.
  - Extensions par sujet plutôt que dans le modèle : `Trip+Cost` (estimation du coût en énergie),
    `Trip+Merge` (fusionner et séparer des trajets), `Trip+Formatting`, `Vehicle+Formatting`.
  - `TripFormatting` porte la mise en forme partagée par les écrans et le PDF ;
    `ReportPeriodBoundary` l'arithmétique calendaire des rapports périodiques.
- **`Services/`** — logique métier et intégrations système, assemblées dans `AppServices`
  (composition root, construit une fois dans `MyTrackApp.init()` avec le `ModelContext` partagé,
  puis injecté par `.environment(...)`) :
  - Enregistrement : `LocationService`, `MotionActivityService`, `DrivingDetector` (la machine à
    états qui décide qu'un trajet commence et se termine), `TripRecorder` (le seul à démarrer et
    arrêter le GPS), `NotificationService`.
  - Rapports : `ReportProfileService`, `ReportGenerationService`, `TripReportPDFRenderer`
    (`nonisolated`, rendu hors du fil principal depuis des `TripReportRow`).
  - Achats : `PurchaseService` — source de vérité unique de l'abonnement, qui coupe la détection
    et prévient quand l'accès tombe.
  - Photos : `VehiclePhotoService` (appelle le proxy), `VehiclePhotoProcessingService` (mène le
    détourage hors de l'écran qui l'a lancé), `VehiclePhotoNormalizer` (cadre commun).
  - Préférences : `LanguageService`, `UnitSettingsService`, `OnboardingService`,
    `ReviewPromptService` — dans `UserDefaults`, parce que ce sont des réglages et non des
    données. Le dernier décide *quand* demander un avis sur l'App Store ; `ReviewPromptModifier`
    pose les étoiles, qui appartiennent à iOS et ne passent donc pas par le catalogue.
  - `FeedbackService`, `TripCostSnapshotService`, `AppLog`, `ModelContext+Saving`.
- **`ViewModels/`** — des `struct` sans état, qui reçoivent le `ModelContext` en paramètre.
- **`Views/`** — par domaine : `Recording/`, `Trips/`, `Vehicles/`, `Reports/`, `Account/`,
  `Onboarding/`, `Legal/`, plus `RootTabView` comme point d'entrée par onglets.
- **`Server/`** — `studio-cutout/` (proxy vers l'API images d'OpenAI, qui détient la clé et le
  prompt) et `feedback/` (relais qui transforme un message des réglages en courriel). Chacun a son
  README. Modifier un worker demande un `wrangler deploy` : le code du dépôt ne suffit pas.

## Conventions observées

- Un type par fichier, nommé comme le fichier.
- Services en classes `@Observable` injectées par l'environnement, jamais de singleton global.
- Les entités SwiftData restent simples ; le calcul et le formatage vivent dans des extensions
  dédiées.
- Les commentaires expliquent **pourquoi**, et gardent trace du bug qui a mené au choix. C'est la
  mémoire du projet : les conserver et les mettre à jour quand le code change.
- Un texte affiché à l'utilisateur est une `LocalizedStringKey` ; une donnée saisie (nom de
  véhicule, de profil) se rend telle quelle. Un ternaire entre deux littéraux passé à `Text` se
  résout en `String` et échappe à la traduction : le typer explicitement.
