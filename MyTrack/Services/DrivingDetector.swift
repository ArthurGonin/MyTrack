//
//  DrivingDetector.swift
//  MyTrack
//
//  State machine that turns raw Core Motion activity samples into
//  start/discard/stop decisions for an automatic trip, driving the shared
//  TripRecorder. GPS starts the instant automotive activity is first seen.
//
//  Both of this machine's verdicts pick the recoverable mistake over the
//  unrecoverable one, because the app can undo exactly one of each pair. A
//  trip recorded as one piece cannot be split — `Trip.separate` only undoes a
//  *merge* — while two trips can be joined in a tap; and a discarded trip is
//  gone without trace, while a spurious one costs one "Non" on a notification.
//  So: keep rather than discard, and cut rather than swallow.
//
//  What makes a trip real is therefore the distance covered, not the time
//  elapsed (see `TripRecorder.minimumAutomaticTripDistance`), and how long a
//  stop is given to prove itself depends on what Core Motion actually says —
//  see `StopReason`. GPS keeps running through that window so the route isn't
//  cut if driving resumes.
//
//  Core Motion only reports activity *changes*, so no decision may rely on a
//  further sample arriving: a steady drive can produce a single automotive
//  sample, and a parked phone left perfectly still produces none at all. Every
//  deadline below is therefore evaluated against wall-clock time and re-armed
//  on a timer, never counted in samples.
//
//  Nor may a decision rely on having *seen* the samples that did arrive: iOS
//  suspends the app, and the live callbacks of that stretch are simply missed.
//  A trip in progress therefore re-reads the activity record itself, on a
//  timer, and trusts that over what it happens to have been told.
//

import Foundation
import UIKit
import OSLog
import CoreLocation
import CoreMotion
import SwiftData
import Observation

/// Why automatic detection is or isn't actually running. `isEnabled` alone
/// only records that the user asked for it — monitoring can still be
/// impossible, and saying so is the difference between a setting that works
/// and one that lies.
enum DrivingDetectionStatus: Equatable {
    /// The user hasn't asked for automatic detection.
    case off
    /// Asked for, and actually watching.
    case running
    /// Asked for, but "Always" location isn't granted — the app is then never
    /// woken to see a drive start.
    case needsAlwaysLocation
    /// Asked for, but Motion & Fitness isn't granted.
    case needsMotionAccess
    /// No motion coprocessor: no activity sample will ever be delivered.
    case unsupportedDevice
    /// Asked for, but there is no active subscription — recording new trips is
    /// what the subscription pays for, so nothing is watched.
    case needsSubscription
}

@Observable
final class DrivingDetector {
    private let motionActivityService: MotionActivityService
    private let tripRecorder: TripRecorder
    private let vehicleService: VehicleService
    private let notificationService: NotificationService
    private let locationService: LocationService
    private let detectionLog: DetectionLog
    private let modelContext: ModelContext

    private(set) var isEnabled: Bool

    /// Poussé depuis AppServices à chaque changement d'abonnement, plutôt que
    /// lu sur PurchaseService : la détection n'a pas à connaître StoreKit, elle
    /// a juste besoin de savoir si elle a le droit de tourner.
    private(set) var hasRecordingAccess: Bool

    /// What detection is really doing, as opposed to what the preference says.
    /// Read by the settings screen so the toggle can't claim to be on while
    /// nothing is watching. Cached rather than computed on demand so SwiftUI
    /// re-renders when it moves: two of its inputs are CoreMotion statics that
    /// no observation can see change.
    private(set) var status: DrivingDetectionStatus = .off

    /// Whether a just-finalized automatic trip still needs a yes/no answer
    /// (the notification + in-app review flow) or gets saved as `.confirmed`
    /// straight away. Plain settable property, unlike `isEnabled`: choosing
    /// this has no permissions to request, so the settings screen and the
    /// onboarding step can both bind to it directly.
    var requiresTripConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(requiresTripConfirmation, forKey: Self.requiresConfirmationKey)
        }
    }

    /// Set only while *this* detector owns the trip being recorded, so a trip
    /// the user started by hand is never silently finalized — nor notified
    /// about as if it had been detected automatically.
    private var recordingStartedAt: Date?
    private var pendingStop: PendingStop?
    private var pendingDecisionTask: Task<Void, Never>?

    /// Vrai dès que la conduite est établie — par un échantillon sûr de Core
    /// Motion, ou par la distance parcourue. Faux tant que le trajet ne repose
    /// que sur un soupçon. Voir `probationWindow`.
    private var isDrivingConfirmed = false
    private var probationTask: Task<Void, Never>?
    private var drivingRecheckTask: Task<Void, Never>?
    private var isMonitoring = false

    /// Un rattrapage est en vol. Le retour au premier plan et un réveil de fond
    /// tombent volontiers ensemble, et deux rattrapages simultanés donneraient
    /// deux requêtes d'historique et deux lignes de journal contradictoires
    /// pour une seule question. Ce n'est pas une garde de correction —
    /// `startProvisionalTrip` est synchrone sur le fil principal, donc deux
    /// tâches ne peuvent pas ouvrir deux trajets — mais de lisibilité.
    private var isCatchingUp = false

    /// La fin de conduite du dernier trajet clos par ce détecteur.
    ///
    /// Il n'existe que pour une chose : ne pas rouvrir un trajet sur les
    /// échantillons « en voiture » qui viennent justement de le clore. On se
    /// gare, la fenêtre d'arrêt s'écoule, le trajet est enregistré — et le
    /// réveil suivant retrouve dans l'historique de Core Motion, qui remonte
    /// cinq minutes, exactement les mêmes échantillons. Rien n'y dit qu'on est
    /// descendu, puisqu'on est encore assis dedans, et le rattrapage rouvrirait
    /// un trajet sur une voiture à l'arrêt.
    ///
    /// Comparé à la date du dernier automobile, et non appliqué comme un délai :
    /// un vrai redémarrage produit un échantillon *postérieur* à cette fin-là
    /// et repart donc aussitôt, là où un délai fixe aurait bloqué celui qui
    /// s'arrête cinq minutes à la boulangerie et repart.
    ///
    /// Sur le disque, parce que le trajet et le réveil qui le suit peuvent
    /// appartenir à deux processus différents : iOS tue l'app garée, la relance
    /// au changement de position significatif suivant, et une valeur seulement
    /// en mémoire vaudrait `nil` au moment exact où elle sert.
    private var lastDrivingEndedAt: Date? {
        didSet {
            UserDefaults.standard.set(
                lastDrivingEndedAt?.timeIntervalSinceReferenceDate,
                forKey: Self.lastDrivingEndedKey
            )
        }
    }

    /// Ce que Core Motion a dit pour ouvrir la fenêtre d'arrêt.
    ///
    /// Les deux réponses possibles n'ont pas du tout la même valeur, et
    /// l'app les traitait pareil :
    ///
    /// - « je marche » (ou je cours, ou je pédale) après « en voiture » ne
    ///   veut dire qu'une chose : la personne est sortie du véhicule. Il n'y a
    ///   rien à attendre.
    /// - « je ne bouge plus » ne tranche rien : c'est un feu rouge, un
    ///   bouchon, un passage à niveau — ou une voiture garée dans laquelle on
    ///   reste assis. Là, il faut de la patience.
    ///
    /// Une seule fenêtre pour les deux devait donc être taillée pour le cas
    /// ambigu, et le cas courant — se garer, sortir, s'en aller — payait cette
    /// patience-là pour rien : cinq minutes de GPS après chaque trajet, et une
    /// notification « avez-vous fait ce trajet ? » qui arrivait cinq minutes
    /// après qu'on avait cessé d'y penser.
    private enum StopReason {
        case leftTheVehicle
        case ambiguous

        init(isMovingUnderOwnPower: Bool) {
            self = isMovingUnderOwnPower ? .leftTheVehicle : .ambiguous
        }
    }

    /// L'arrêt en cours d'évaluation : depuis quand, et sur quel signal.
    ///
    /// Les deux ensemble plutôt que deux propriétés côte à côte : elles sont
    /// posées et effacées d'un seul geste, et rien ne peut les désynchroniser.
    private struct PendingStop {
        let since: Date
        let reason: StopReason
    }

    /// Les deux fenêtres système à enchaîner pour atteindre « Toujours ».
    ///
    /// Leur ordre n'est pas une question de présentation : c'est la seule
    /// façon d'obtenir la seconde. iOS ne réserve la fenêtre de passage à
    /// « Toujours » qu'à une app qui a déjà « Lorsque l'app est active » et
    /// qui n'a encore jamais demandé « Toujours » — une fois, et une seule.
    ///
    /// Demander `.always` d'emblée, sans rien avoir encore, ne demande donc
    /// pas « Toujours » : ça affiche la fenêtre de `.whenInUse`, qui ne
    /// propose que « Lorsque l'app est active », et ça dépense le coup unique
    /// au passage. C'était le bug : la seconde fenêtre était bien demandée
    /// ensuite, mais l'appel ne faisait plus rien — sans erreur, sans rappel,
    /// sans rien. L'app restait sur « Lorsque l'app est active », donc jamais
    /// réveillée en arrière-plan, et la détection automatique ne pouvait pas
    /// démarrer.
    private enum LocationPrompt {
        case whenInUse
        case always
    }

    /// "Always" is only reachable in two steps — the initial When In Use
    /// prompt, then a separate upgrade prompt once that's granted. Set for the
    /// duration of one enable() call so both are chained automatically instead
    /// of requiring the user to come back and enable again after each prompt.
    /// Not re-armed on relaunch, so declining the upgrade once doesn't turn
    /// into a repeated system prompt on every future cold start.
    private var isEscalatingToAlways = false
    private var lastEscalationRequestStatus: CLAuthorizationStatus?
    /// Falls back after a prompt with no reply, since declining the upgrade
    /// prompt (staying at "When In Use") doesn't always produce another
    /// authorization-change callback for escalateToAlwaysIfNeeded to react to.
    private var escalationTimeoutTask: Task<Void, Never>?
    /// Combien de temps l'escalade vers « Toujours » reste armée sans nouvelle.
    ///
    /// C'est un filet, pas un rythme d'interface. Il n'existe que pour le cas
    /// où iOS ne montre rien et ne rappellera jamais — typiquement quand la
    /// fenêtre de passage à « Toujours », qu'iOS ne propose qu'une seule fois,
    /// a déjà été dépensée. Il doit donc être plus long que le temps qu'un
    /// humain met à lire une fenêtre d'autorisation et à se décider.
    ///
    /// Il valait 10 s : le compte à rebours courait pendant que l'utilisateur
    /// lisait la fenêtre et expirait avant sa réponse, qui arrivait ensuite sur
    /// une escalade déjà désarmée — `escalateToAlwaysIfNeeded` s'arrêtait à sa
    /// garde et ne demandait plus rien. Un délai d'autorisation se dimensionne
    /// sur un temps humain, jamais sur un temps machine.
    private static let escalationTimeout: Duration = .seconds(90)

    /// Ce que l'onboarding accepte d'attendre avant de passer à la suite.
    ///
    /// Séparé de `escalationTimeout` à dessein : l'escalade peut rester armée
    /// longtemps sans que l'écran ait à se figer d'autant. Sans cette
    /// séparation, allonger le filet ci-dessus aurait bloqué l'onboarding
    /// pendant tout ce temps dans le cas justement où iOS ne montre rien.
    ///
    /// Passé ce délai l'onboarding avance ; une fenêtre système encore ouverte
    /// reste posée par-dessus, puisqu'elle n'appartient pas à l'écran qu'elle
    /// recouvre, et la réponse sera prise en compte quand elle arrivera.
    private static let onboardingWaitTimeout: Duration = .seconds(20)

    /// Le battement laissé à une fenêtre système pour finir de se refermer
    /// avant qu'on pose la suivante. Demander la seconde depuis le rappel
    /// d'autorisation qui vient d'annoncer la réponse à la première n'est pas
    /// fiable : CoreLocation peut avaler la demande sans rien montrer.
    private static let promptSettlingDelay: Duration = .milliseconds(500)

    /// How far back to look for a drive already under way when monitoring
    /// arms. Long enough to catch a trip that began before the app was woken,
    /// short enough that the reading still describes now.
    private static let recentActivityLookback: TimeInterval = 300

    /// Ce qu'on attend, la conduite arrêtée, avant de clore le trajet.
    ///
    /// Deux valeurs et non une, parce que la question posée n'est pas la même
    /// — voir `StopReason`. La personne a quitté la voiture : quatre-vingt-dix
    /// secondes suffisent, le temps qu'elle y revienne si elle avait juste
    /// fait le tour du véhicule. Elle est seulement immobile : trois minutes,
    /// de quoi passer un feu rouge interminable ou un passage à niveau.
    ///
    /// Trois minutes et non cinq, parce que la fenêtre longue prenait un pari
    /// irréversible pour en éviter un réversible : cinq minutes avalent un
    /// arrêt à la station-service ou un dépôt à l'école, et le trajet unique
    /// qui en sort ne peut plus être coupé — alors que deux trajets se
    /// fusionnent d'un geste, et se re-séparent ensuite.
    private static let stopWindowOnFoot: TimeInterval = 90
    private static let stopWindowStandingStill: TimeInterval = 180

    private static func stopWindow(for reason: StopReason) -> TimeInterval {
        switch reason {
        case .leftTheVehicle: stopWindowOnFoot
        case .ambiguous: stopWindowStandingStill
        }
    }

    /// Vrai quand l'échantillon dit que la personne se déplace par ses propres
    /// moyens. Le pendant vivant de `DrivingReading.isMovingUnderOwnPower`,
    /// pour que la politique soit écrite une seule fois.
    private static func isMovingUnderOwnPower(_ activity: CMMotionActivity) -> Bool {
        activity.walking || activity.running || activity.cycling
    }

    /// Tous les combien, trajet en cours, on va relire l'historique de Core
    /// Motion au lieu d'attendre qu'il parle.
    ///
    /// Un échantillon vivant n'arrive que si l'app tourne. Suspendue — ce
    /// qu'iOS fait sans prévenir — elle ne voit rien passer, et se retrouve
    /// dans l'un des deux mauvais états : elle croit la conduite finie sur un
    /// échantillon dépassé, et coupe le trajet et le GPS en pleine route ; ou
    /// elle la croit en cours longtemps après l'arrêt, et laisse le GPS
    /// tourner. La requête d'historique, elle, est complète quoi qu'il soit
    /// arrivé à l'app : c'est la seule lecture sur laquelle on puisse compter.
    ///
    /// Une minute : assez rare pour ne rien coûter, assez fréquent pour qu'une
    /// relecture tombe toujours à l'intérieur de la plus courte des fenêtres
    /// d'arrêt. C'est cette relecture qui rend ces fenêtres raccourcissables :
    /// sans elle, une fenêtre courte couperait des trajets en deux sur un
    /// échantillon que l'app, suspendue, n'aurait pas vu se démentir.
    private static let drivingRecheckInterval: Duration = .seconds(60)

    /// Combien de temps un trajet ouvert sur un simple soupçon a pour faire ses
    /// preuves.
    ///
    /// Le GPS s'allume désormais sur un échantillon « en voiture » que Core
    /// Motion donne lui-même pour peu sûr (voir `handle`). C'est le seul moyen
    /// d'avoir les points du *début* du trajet : le verdict sûr arrive une à
    /// trois minutes plus tard — huit cents mètres en ville, plusieurs
    /// kilomètres sur voie rapide — et rien ne peut retrouver après coup des
    /// positions qui n'ont jamais été mesurées, iOS n'en gardant aucun
    /// historique. En échange il faut savoir éteindre vite quand le soupçon
    /// était faux, sans quoi le moindre capteur qui se trompe laisserait le GPS
    /// tourner jusqu'au bout d'une fenêtre d'arrêt.
    ///
    /// Deux minutes, parce que la preuve attendue est d'avoir parcouru les
    /// 300 m de `minimumAutomaticTripDistance` : ça fait 9 km/h de moyenne,
    /// sous la vitesse d'un cycliste, donc franchi par n'importe quelle
    /// conduite réelle — y compris un départ retenu par un feu à cinquante
    /// mètres de chez soi. À une minute il aurait fallu tenir 18 km/h de
    /// moyenne, et de vrais trajets urbains se seraient fait effacer.
    ///
    /// Ce qui est jeté ici l'est sans un mot : aucune notification ne part de
    /// ce chemin — elles ne partent que de `finalizeTrip` — et l'utilisateur
    /// n'a rien vu qu'il faille lui retirer.
    private static let probationWindow: TimeInterval = 120

    /// De combien un trajet peut être daté avant l'instant où on l'ouvre.
    ///
    /// Core Motion date ses échantillons du moment où l'activité a commencé, et
    /// non du moment où il le dit : c'est cette date-là qui donne le vrai début
    /// du trajet, et la retenir vaut souvent une dizaine de secondes de route.
    /// Bornée, parce qu'un échantillon peut couvrir une longue période : un
    /// trajet daté loin avant son premier point GPS afficherait une durée que
    /// sa distance ne justifie pas.
    private static let maxBackdating: TimeInterval = 60

    /// Depuis combien de temps au plus un « en voiture » peut dater pour qu'on
    /// ouvre encore un trajet dessus.
    ///
    /// `recentActivityLookback` est la fenêtre qu'on *interroge* ; celle-ci est
    /// la fenêtre qu'on *croit*. Les deux diffèrent parce que la question n'est
    /// pas la même : on remonte cinq minutes pour être sûr de trouver le
    /// dernier changement, mais on n'ouvre un trajet que si ce changement
    /// décrit encore maintenant. Un « en voiture » vieux de quatre minutes
    /// suivi de rien du tout, c'est une voiture garée depuis quatre minutes.
    ///
    /// Cent quatre-vingts secondes, c'est-à-dire `stopWindowStandingStill` : un
    /// trajet en cours qui aurait vu ce silence-là se serait clos tout seul, et
    /// rouvrir maintenant ce qu'on aurait fermé alors n'aurait aucun sens.
    private static let automotiveSuspicionMaxAge: TimeInterval = 180

    /// La vitesse Doppler à partir de laquelle un point livré hors trajet vaut
    /// à lui seul un soupçon de conduite.
    ///
    /// Huit mètres par seconde, soit 29 km/h — et c'est la borne *basse* de
    /// l'estimation qui doit la franchir. Le seuil n'a pas à séparer la voiture
    /// du vélo, il a à séparer un véhicule d'un piéton, et il n'ouvre qu'une
    /// probation. Plus haut, on manquerait le trajet urbain lent qui est tout
    /// l'objet de ce changement : une rue limitée à trente est une rue
    /// ordinaire.
    private static let reportedDrivingSpeed: CLLocationSpeed = 8

    /// Le même seuil pour la vitesse *déduite* de deux réveils, et il est plus
    /// bas : six mètres par seconde, soit 21,6 km/h.
    ///
    /// Plus bas parce que la mesure est d'une autre nature — une moyenne de
    /// porte à porte, feux rouges compris. Une voiture en ville tient 20 à
    /// 30 km/h de moyenne, un piéton 5, et la marge reste confortable.
    ///
    /// Et il faut être clair sur ce que ce déclencheur-ci ne peut pas faire :
    /// iOS n'émet un changement significatif qu'au-delà de cinq cents mètres,
    /// et pas plus d'une fois toutes les cinq minutes. Deux réveils consécutifs
    /// en ville lente peuvent donc n'afficher que 6 km/h de moyenne et ne rien
    /// déclencher — et par construction, le *premier* réveil d'un trajet n'a
    /// aucun point de comparaison. C'est un filet pour la route, pas une
    /// détection rapide pour la ville. La ville, c'est le soupçon de Core
    /// Motion élargi qui la porte.
    private static let impliedDrivingSpeed: CLLocationSpeed = 6

    /// Au-delà de quoi une vitesse ne décrit plus un véhicule routier — un
    /// train à grande vitesse, un avion, ou une mesure aberrante. 55 m/s, soit
    /// 198 km/h, juste sous le plafond que `TripRecorder.maxPlausibleSpeed`
    /// applique déjà aux points de la trace.
    private static let maxRoadSpeed: CLLocationSpeed = 55

    /// La vitesse instantanée qui prouve un véhicule, quelle que soit la
    /// distance parcourue. Voir `endProbation`.
    ///
    /// 8,3 m/s, soit 30 km/h. Personne ne marche ni ne court à cette
    /// vitesse-là. Un cycliste rapide y arrive : il partira alors en trajet, et
    /// c'est la question « avez-vous fait ce trajet ? » qui tranchera — la même
    /// répartition des rôles que pour le bus et le train, déjà écrite dans
    /// `TripRecorder.minimumAutomaticTripDistance`.
    private static let confirmingSpeed: CLLocationSpeed = 8.3
    private static let preferenceKey = "isAutoDetectionEnabled"
    private static let requiresConfirmationKey = "autoDetectionRequiresConfirmation"
    private static let lastDrivingEndedKey = "lastAutomaticDrivingEndedAt"

    init(
        motionActivityService: MotionActivityService,
        tripRecorder: TripRecorder,
        vehicleService: VehicleService,
        notificationService: NotificationService,
        locationService: LocationService,
        detectionLog: DetectionLog,
        modelContext: ModelContext,
        hasRecordingAccess: Bool
    ) {
        self.hasRecordingAccess = hasRecordingAccess
        self.motionActivityService = motionActivityService
        self.tripRecorder = tripRecorder
        self.vehicleService = vehicleService
        self.notificationService = notificationService
        self.locationService = locationService
        self.detectionLog = detectionLog
        self.modelContext = modelContext
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        // Absent key means "never set" rather than "chose automatic": default
        // to true so upgrading users keep today's always-ask behavior instead
        // of being silently switched to auto-accept.
        self.requiresTripConfirmation = UserDefaults.standard.object(forKey: Self.requiresConfirmationKey) as? Bool ?? true
        // `object(forKey:)` et non `double(forKey:)` : la clé absente rendrait
        // zéro, c'est-à-dire le 1er janvier 2001, et tout échantillon lui serait
        // postérieur — la garde ne servirait plus à rien au premier lancement.
        // Les observateurs ne se déclenchent pas dans un `init`, donc rien n'est
        // réécrit sur le disque au passage.
        self.lastDrivingEndedAt = (UserDefaults.standard.object(forKey: Self.lastDrivingEndedKey) as? Double)
            .map(Date.init(timeIntervalSinceReferenceDate:))

        // "Always" location can be granted or revoked from Settings while the
        // app isn't running, so monitoring is re-evaluated on every change
        // rather than trusting the status seen at launch.
        locationService.onAuthorizationChange = { [weak self] _ in
            self?.escalateToAlwaysIfNeeded()
            self?.refresh()
        }

        // Re-arms monitoring on every fresh process start — normal relaunch
        // after a force-quit, or a background relaunch triggered by a
        // significant location change — since isEnabled always starts false
        // in a brand new instance otherwise.
        refresh()

        locationService.onBackgroundWake = { [weak self] wake in
            self?.catchUpWithDrivingAlreadyUnderWay(triggeredBy: .backgroundWake, wokenBy: wake)
        }
    }

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.preferenceKey)
        isEscalatingToAlways = true
        lastEscalationRequestStatus = nil
        escalateToAlwaysIfNeeded()
        refresh()
    }

    /// Le point d'entrée unique pour allumer la détection automatique, d'où
    /// qu'on le demande — l'étape d'onboarding comme l'interrupteur des
    /// réglages.
    ///
    /// Les deux écrans enchaînaient chacun leur propre séquence, et les deux
    /// avaient divergé : l'un attendait la fin des demandes système, l'autre
    /// repartait aussitôt ; l'un demandait les notifications, l'autre les
    /// demandait ailleurs. Surtout, l'écran des réglages annonçait son
    /// résultat à partir de l'état lu *avant* les fenêtres, donc sans jamais
    /// savoir ce que l'utilisateur venait de répondre. La séquence vit
    /// désormais ici, à côté de l'escalade de position qu'elle pilote, et rend
    /// l'état réel une fois tout retombé.
    ///
    /// Les notifications n'en font délibérément pas partie : un trajet détecté
    /// est enregistré qu'elles soient accordées ou non — seule la confirmation
    /// change de chemin et se fait alors dans l'app. Elles ont leur propre
    /// ligne dans les réglages plutôt que d'être un préalable à celui-ci.
    @discardableResult
    func requestActivation() async -> DrivingDetectionStatus {
        // Rien à demander sur un appareil sans coprocesseur de mouvement : la
        // détection ne peut pas y fonctionner, et faire surgir des fenêtres
        // d'autorisation pour ça ne mènerait nulle part.
        guard motionActivityService.isAvailable else {
            enable()
            return status
        }

        // Motion d'abord : la surveillance refuse de démarrer sans lui, et le
        // laisser à `startActivityUpdates` ferait surgir sa fenêtre à un
        // lancement ultérieur, loin du geste qui l'a demandée.
        await motionActivityService.requestAuthorization()

        // La préférence se pose même si une autorisation manque encore. Elle
        // dit ce que l'utilisateur veut, `status` dit ce qui tourne vraiment —
        // c'est toute la raison d'être des deux. L'accorder plus tard depuis
        // les Réglages d'iOS suffit alors à démarrer la surveillance, sans
        // avoir à revenir rebasculer un interrupteur éteint entre-temps.
        enable()
        await waitForAuthorizationSettled()
        refresh()
        return status
    }

    /// Stops watching motion activity. A trip already in progress is left
    /// running — TripRecorder keeps recording it via the manual-mode path
    /// until finalized, rather than being cut off abruptly.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.preferenceKey)
        stopEscalating()
        stopMonitoring()
        resetState()
        status = currentStatus
    }

    /// Remet les deux préférences de la détection dans l'état d'un premier
    /// lancement — appelée par `AppServices.eraseAllData`, qui promet une app
    /// d'avant tout premier lancement. `disable()` a déjà éteint la
    /// surveillance ; ici on efface ce qui reste sur le disque.
    func resetToDefaults() {
        isEnabled = false
        requiresTripConfirmation = true
        // Effacées *après* les affectations : le `didSet` de
        // `requiresTripConfirmation` réenregistrerait sinon la clé qu'on vient
        // d'effacer, et l'app cesserait de distinguer « jamais choisi » de
        // « choisi ainsi » (même piège que `LanguageService.resetToSystemDefault`).
        UserDefaults.standard.removeObject(forKey: Self.preferenceKey)
        UserDefaults.standard.removeObject(forKey: Self.requiresConfirmationKey)
        lastDrivingEndedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.lastDrivingEndedKey)
        status = currentStatus
    }

    /// Ouvre ou ferme la détection selon l'abonnement. La *préférence* de
    /// l'utilisateur (`isEnabled`) n'est jamais touchée : reprendre son
    /// abonnement doit faire repartir la détection sans avoir à re-basculer un
    /// réglage qu'on aurait éteint dans son dos.
    func setRecordingAccess(_ hasAccess: Bool) {
        guard hasRecordingAccess != hasAccess else { return }
        hasRecordingAccess = hasAccess

        guard !hasAccess else {
            refresh()
            return
        }

        // L'abonnement tombe au milieu d'un trajet : le couper net donnerait
        // une distance fausse dans un rapport de frais, et arrêter la
        // surveillance tout de suite laisserait le trajet ouvert pour toujours,
        // GPS allumé, puisque plus rien ne viendrait constater sa fin. Le
        // trajet en cours va donc au bout ; c'est resetState(), à la
        // finalisation, qui coupera.
        guard !ownsTripInProgress else {
            status = currentStatus
            return
        }
        stopMonitoringForLostAccess()
    }

    private var ownsTripInProgress: Bool {
        recordingStartedAt != nil && tripRecorder.isRecording
    }

    private func stopMonitoringForLostAccess() {
        stopMonitoring()
        status = currentStatus
        detectionLog.record("Auto-detection stopped: no active subscription.")
    }

    /// Waits until the "Always" escalation started by enable() has settled —
    /// granted, denied, or given up on after escalationTimeout with no
    /// reply. Onboarding awaits this so it only moves on once the user has
    /// actually answered every prompt, instead of racing ahead of them.
    func waitForAuthorizationSettled() async {
        let deadline = ContinuousClock.now + Self.onboardingWaitTimeout
        while isEscalatingToAlways, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The moment driving actually stopped for the trip this detector owns, if
    /// it has stopped but isn't finalized yet. Lets a stop triggered from the
    /// app end the trip where the driving ended, rather than padding it with
    /// the minutes spent parked inside the stop-confirmation window.
    var ownedTripDrivingStoppedAt: Date? {
        recordingStartedAt == nil ? nil : pendingStop?.since
    }

    /// Call when the trip this detector started was ended from somewhere else —
    /// the user tapping Stop in the app. Without it the leftover state would
    /// later attach itself to a trip the user starts by hand, and finalize that
    /// one behind their back.
    func forgetOwnedTrip() {
        resetState()
    }

    /// Chains the two system prompts needed to reach "Always" — see
    /// isEscalatingToAlways — deduplicated per status so a re-delivered
    /// authorization callback for the same status doesn't re-show a prompt
    /// the user just answered.
    private func escalateToAlwaysIfNeeded() {
        guard isEscalatingToAlways else { return }
        let status = locationService.authorizationStatus

        switch status {
        // Rien n'a encore été accordé : on demande « Lorsque l'app est
        // active », et surtout pas « Toujours » — voir LocationPrompt.
        // Demander « Toujours » ici afficherait exactement la même fenêtre,
        // mais dépenserait la demande unique dont dépend l'étape suivante.
        case .notDetermined:
            guard lastEscalationRequestStatus != status else { return }
            lastEscalationRequestStatus = status
            requestPrompt(.whenInUse)

        // « Lorsque l'app est active » est accordé : c'est maintenant, et
        // seulement maintenant, qu'iOS montre la fenêtre de passage à
        // « Toujours ».
        case .authorizedWhenInUse:
            guard lastEscalationRequestStatus != status else { return }
            lastEscalationRequestStatus = status
            requestPrompt(.always)

        default:
            // Reached "Always", or the user declined outright — either way
            // there is nothing left to escalate toward.
            stopEscalating()
        }
    }

    /// Pose une fenêtre système, après avoir laissé la précédente se refermer
    /// (`promptSettlingDelay`) et armé le filet qui désarmera l'escalade si
    /// rien ne revient jamais.
    private func requestPrompt(_ prompt: LocationPrompt) {
        armEscalationTimeout()
        // Sur le fil principal : `CLLocationManager` demande à être piloté
        // depuis un fil qui a une boucle d'exécution, et c'est une fenêtre
        // qu'on fait apparaître à l'écran.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.promptSettlingDelay)
            guard let self else { return }
            switch prompt {
            case .whenInUse:
                detectionLog.record("Asking for \"When In Use\" location.")
                locationService.requestWhenInUseAuthorization()
            case .always:
                detectionLog.record("Asking to upgrade location to \"Always\".")
                locationService.requestAlwaysAuthorization()
            }
        }
    }

    /// Il n'y a plus de fenêtre à attendre : ce qui patiente sur l'escalade
    /// (l'onboarding) peut reprendre tout de suite.
    private func stopEscalating() {
        isEscalatingToAlways = false
        escalationTimeoutTask?.cancel()
    }

    private func armEscalationTimeout() {
        escalationTimeoutTask?.cancel()
        escalationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.escalationTimeout)
            guard !Task.isCancelled else { return }
            self?.isEscalatingToAlways = false
        }
    }

    /// Recomputes `status` and arms monitoring if that has become possible.
    ///
    /// Must be called when the app returns to the foreground: Motion & Fitness
    /// can be granted from the Settings app, and CoreMotion reports that to
    /// nobody — without this, the user grants access, comes back, and finds a
    /// toggle still claiming to be blocked while nothing watches.
    func refresh() {
        status = currentStatus
        startMonitoringIfPossible()
        // Le rattrapage est ici, et non dans `startMonitoringIfPossible`, qui
        // sort à sa toute première garde (`guard !isMonitoring`) quand la
        // surveillance tourne déjà. Revenir dans l'app en roulant ne
        // déclenchait donc rien du tout — or c'est le seul moment où
        // l'utilisateur regarde : il ouvre l'app en voiture, ne voit aucun
        // trajet, et conclut, à raison, que la détection ne marche pas.
        //
        // `startMonitoringIfPossible` n'a que cet appelant-ci, donc rien ne
        // peut appeler deux fois. Le dernier réveil connu est passé pour que le
        // retour au premier plan dispose de la même vitesse que lui.
        catchUpWithDrivingAlreadyUnderWay(
            triggeredBy: .foreground, wokenBy: locationService.lastBackgroundWake
        )
    }

    private var currentStatus: DrivingDetectionStatus {
        guard isEnabled else { return .off }
        // Avant les permissions : c'est la cause la plus actionnable, et celle
        // qui explique vraiment pourquoi plus rien ne s'enregistre.
        guard hasRecordingAccess else { return .needsSubscription }
        guard motionActivityService.isAvailable else { return .unsupportedDevice }
        guard locationService.authorizationStatus == .authorizedAlways else { return .needsAlwaysLocation }
        guard motionActivityService.isAuthorized else { return .needsMotionAccess }
        return .running
    }

    /// Arms monitoring only when it can actually work — see `status`.
    private func startMonitoringIfPossible() {
        guard !isMonitoring else { return }

        switch status {
        case .off:
            return
        case .needsSubscription:
            detectionLog.record("Auto-detection is on but there is no active subscription — monitoring stays off.")
            return
        case .unsupportedDevice:
            detectionLog.record("Motion activity is unavailable on this device — auto-detection can't run.")
            return
        case .needsAlwaysLocation:
            detectionLog.record("Auto-detection is on but \"Always\" location isn't granted — monitoring stays off.")
            return
        case .needsMotionAccess:
            // Never let arming monitoring be what asks for Motion & Fitness:
            // startActivityUpdates raises the prompt on its own, so a cold
            // start with the preference still on would show it straight away,
            // outside the onboarding step that is meant to introduce it.
            // Asking is done explicitly, and only there.
            detectionLog.record("Motion & Fitness isn't granted — monitoring stays off rather than prompting from here.")
            return
        case .running:
            break
        }

        isMonitoring = true
        locationService.startSignificantLocationMonitoring()
        motionActivityService.startMonitoring { [weak self] activity in
            self?.handle(activity)
        }
        // La seule ligne positive du journal : sans elle, « armé » et « jamais
        // atteint » se lisent pareil, c'est-à-dire pas du tout.
        detectionLog.record("Monitoring armed.")
    }

    /// Ce qu'un rattrapage a trouvé, et sur quelle foi.
    ///
    /// Nommé plutôt qu'un `Bool` : c'est la raison, et non le verdict, qui
    /// expliquera un trajet manqué quand on relira le journal.
    private enum CatchUpVerdict {
        /// Core Motion lit « en voiture », sûr, et rien ne dit qu'on est sorti.
        case confirmedAutomotive
        /// « En voiture », mais peu sûr : le soupçon d'un démarrage.
        case suspectedAutomotive
        /// « En voiture » sûr, puis plus rien qui bouge, et personne n'est
        /// descendu : un feu, un bouchon, une barrière de péage.
        case stoppedInsideAVehicle
        /// Le GPS mesure une vitesse de véhicule. Core Motion n'est pas
        /// consulté — voir `speedVerdict`.
        case measuredSpeed
        /// Deux réveils successifs assez éloignés pour n'être pas un piéton.
        case impliedSpeed

        /// Seul le premier cas se passe de probation.
        var isConfirmed: Bool {
            if case .confirmedAutomotive = self { return true }
            return false
        }

        /// Pour le journal, et pas pour l'écran : aucune traduction à écrire.
        var logDescription: String {
            switch self {
            case .confirmedAutomotive: "confident automotive"
            case .suspectedAutomotive: "low-confidence automotive"
            case .stoppedInsideAVehicle: "stopped, still in the vehicle"
            case .measuredSpeed: "measured GPS speed"
            case .impliedSpeed: "speed implied between two wakes"
            }
        }
    }

    /// D'où vient un rattrapage.
    ///
    /// Ce n'est pas cosmétique : `refresh()` en déclenche un à chaque retour au
    /// premier plan, et vingt lignes « rien vu » par jour noieraient dans le
    /// journal les trois qui comptent. Un refus n'y est gardé que lorsqu'il y
    /// avait quelque chose à décider — un vrai réveil de fond, ou un « en
    /// voiture » dans l'historique.
    private enum CatchUpTrigger {
        case backgroundWake
        case foreground
    }

    /// Faut-il ouvrir un trajet sur ce que Core Motion a enregistré ?
    ///
    /// C'est ici que le rattrapage cesse d'être plus timide que la décision en
    /// direct. `handle(_:)` allume le GPS sur un « en voiture » que Core Motion
    /// donne lui-même pour peu sûr ; ce chemin-ci exigeait un échantillon sûr
    /// *et* qu'il fût le dernier de la fenêtre. La politique généreuse était
    /// donc celle qui ne peut pas s'exécuter — une app suspendue ne reçoit
    /// aucun échantillon vivant — et la timide celle qui décidait vraiment.
    ///
    /// Trois cas ouvrent, trois refusent : le refus demande une preuve, pas un
    /// doute. C'est la règle du fichier prise dans l'autre sens.
    private static func catchUpVerdict(
        for reading: MotionActivityService.DrivingReading,
        lastDrivingEndedAt: Date?,
        at now: Date
    ) -> CatchUpVerdict? {
        guard let lastAutomotiveAt = reading.lastAutomotiveAt else { return nil }

        // Les échantillons qui ont clos le trajet précédent, et qu'on retrouve
        // dans l'historique parce qu'il remonte plus loin qu'eux. Voir
        // `lastDrivingEndedAt`.
        if let lastDrivingEndedAt, lastAutomotiveAt <= lastDrivingEndedAt { return nil }

        // Descendu du véhicule depuis : il n'y a pas de trajet à reprendre.
        if reading.leftVehicleAt != nil { return nil }

        // Trop vieux pour décrire maintenant. Voir `automotiveSuspicionMaxAge`.
        guard now.timeIntervalSince(lastAutomotiveAt) <= automotiveSuspicionMaxAge else { return nil }

        if reading.isAutomotive { return .confirmedAutomotive }
        guard reading.lastAutomotiveWasConfident else { return .suspectedAutomotive }
        return .stoppedInsideAVehicle
    }

    /// Ce que la vitesse du réveil dit, Core Motion n'étant pas consulté.
    ///
    /// C'est le second déclencheur, et il existe parce que le premier a un
    /// angle mort connu : téléphone dans une poche, en ville, à l'arrêt un feu
    /// sur deux, Core Motion hésite entre « je marche » et « en voiture » et ne
    /// donne souvent que du `.low`. La vitesse ne connaît pas cette
    /// hésitation — quand le GPS mesure quarante kilomètres-heure, un « je
    /// marche » est simplement faux.
    private static func speedVerdict(for wake: LocationService.BackgroundWake) -> CatchUpVerdict? {
        if let reported = wake.reportedSpeed, (reportedDrivingSpeed...maxRoadSpeed).contains(reported) {
            return .measuredSpeed
        }
        if let implied = wake.impliedSpeed, (impliedDrivingSpeed...maxRoadSpeed).contains(implied) {
            return .impliedSpeed
        }
        return nil
    }

    /// Ce qu'il faut lire pour comprendre après coup pourquoi un trajet n'a pas
    /// démarré. Sans ces chiffres, un rattrapage refusé est indiscernable d'un
    /// rattrapage jamais tenté.
    private static func logSummary(
        of reading: MotionActivityService.DrivingReading, at now: Date
    ) -> String {
        let automotive = reading.lastAutomotiveAt.map {
            let age = Int(now.timeIntervalSince($0))
            return "automotive \(age)s ago (\(reading.lastAutomotiveWasConfident ? "confident" : "low"))"
        } ?? "no automotive sample"
        let exit = reading.leftVehicleAt.map {
            "left the vehicle \(Int(now.timeIntervalSince($0)))s ago"
        } ?? "no exit seen"
        return "\(automotive), \(exit)"
    }

    /// Core Motion delivers only changes from the moment monitoring arms, so a
    /// drive already in progress produces nothing until it ends. This is the
    /// path that catches it — most importantly when a significant location
    /// change has just relaunched the app mid-journey, which is exactly the
    /// case automatic detection exists to cover.
    ///
    /// `wake` porte ce que le réveil a mesuré, quand c'en est un ; il vaut
    /// `nil` quand le rattrapage vient de l'armement de la surveillance.
    private func catchUpWithDrivingAlreadyUnderWay(
        triggeredBy trigger: CatchUpTrigger,
        wokenBy wake: LocationService.BackgroundWake? = nil
    ) {
        guard !isCatchingUp else { return }
        guard isEnabled, isMonitoring, !tripRecorder.isRecording else { return }
        isCatchingUp = true

        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }

        let taskToComplete = bgTaskId

        Task { [weak self] in
            defer {
                if taskToComplete != .invalid {
                    UIApplication.shared.endBackgroundTask(taskToComplete)
                }
            }
            guard let self else { return }
            defer { isCatchingUp = false }

            let now = Date()
            let reading = await motionActivityService.recentDriving(lookingBack: Self.recentActivityLookback)
            // Conditions can have changed while the query was in flight.
            guard isEnabled, isMonitoring, !tripRecorder.isRecording else { return }

            let motionVerdict = Self.catchUpVerdict(
                for: reading, lastDrivingEndedAt: lastDrivingEndedAt, at: now
            )
            // La vitesse en second, et sans le veto de Core Motion : quand le
            // GPS mesure quarante kilomètres-heure, un « je marche » est
            // simplement faux. `lastDrivingEndedAt` ne s'y applique pas non
            // plus — il parle d'échantillons périmés, alors qu'une vitesse
            // parle de maintenant, et repartir aussitôt après s'être garé est
            // un vrai départ.
            guard let verdict = motionVerdict ?? wake.flatMap(Self.speedVerdict(for:)) else {
                if trigger == .backgroundWake || reading.lastAutomotiveAt != nil {
                    detectionLog.record(
                        "Catch-up found nothing: \(Self.logSummary(of: reading, at: now))."
                    )
                }
                return
            }

            let drivingSince: Date
            switch verdict {
            case .suspectedAutomotive:
                // Même règle que `handle(_:)` : un « en voiture » peu sûr est ce
                // que Core Motion produit au *début* d'une conduite, et sa date
                // de début est alors la vraie heure de départ — à
                // `maxBackdating` près.
                drivingSince = max(
                    reading.lastAutomotiveAt ?? now, now.addingTimeInterval(-Self.maxBackdating)
                )
            case .confirmedAutomotive, .stoppedInsideAVehicle, .measuredSpeed, .impliedSpeed:
                // Maintenant, et non le début de la conduite : celle-ci peut
                // durer depuis un quart d'heure dont le GPS éteint n'a pas un
                // seul point, et un trajet daté de là afficherait une durée que
                // sa distance ne justifie pas.
                drivingSince = now
            }

            detectionLog.record(
                "Catch-up: \(verdict.logDescription) — \(Self.logSummary(of: reading, at: now))."
            )
            clearPendingDecision()
            startProvisionalTrip(confirmed: verdict.isConfirmed, drivingSince: drivingSince)
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        locationService.stopSignificantLocationMonitoring()
        motionActivityService.stopMonitoring()
    }

    private func resetState() {
        recordingStartedAt = nil
        isDrivingConfirmed = false
        probationTask?.cancel()
        probationTask = nil
        clearPendingDecision()
        drivingRecheckTask?.cancel()
        drivingRecheckTask = nil
        // Le trajet qui était en cours quand l'abonnement est tombé vient de se
        // terminer : c'est ici, et pas avant, qu'on cesse de surveiller.
        if !hasRecordingAccess, isMonitoring {
            stopMonitoringForLostAccess()
        }
    }

    /// La garde de confiance ne vaut plus pour les deux sens, et c'est tout le
    /// changement : **un soupçon suffit à allumer le GPS, jamais à l'éteindre.**
    ///
    /// C'est la même règle que celle écrite en tête de ce fichier — préférer
    /// l'erreur qui se rattrape — appliquée au démarrage. Démarrer pour rien se
    /// répare tout seul : le trajet part en probation et s'efface sans un mot.
    /// Démarrer trop tard ne se répare pas du tout, les mètres non enregistrés
    /// n'existant nulle part. À l'autre bout, couper une trace en pleine route
    /// sur un échantillon peu sûr serait la faute irréversible, donc l'arrêt
    /// continue d'exiger un signal sûr.
    private func handle(_ activity: CMMotionActivity) {
        if activity.automotive {
            // Driving (again): any pending stop or discard decision is off —
            // mais sur la foi d'un signal sûr seulement. Un soupçon ne doit pas
            // prolonger un trajet que la fenêtre d'arrêt s'apprête à clore.
            if activity.confidence != .low {
                clearPendingDecision()
            }

            if !tripRecorder.isRecording {
                startProvisionalTrip(
                    confirmed: activity.confidence != .low,
                    drivingSince: Self.tripStart(for: activity)
                )
            } else if activity.confidence != .low {
                confirmDriving()
            }
            return
        }

        guard activity.confidence != .low else { return }

        // This detector only ends trips it started itself: a manual recording
        // belongs to the user until they stop it by hand.
        guard recordingStartedAt != nil, tripRecorder.isRecording else { return }

        noteStop(at: Date(), reason: StopReason(isMovingUnderOwnPower: Self.isMovingUnderOwnPower(activity)))
        evaluatePendingDecision()
    }

    /// L'heure à laquelle dater un trajet ouvert sur cet échantillon. Voir
    /// `maxBackdating`.
    private static func tripStart(for activity: CMMotionActivity) -> Date {
        max(activity.startDate, Date().addingTimeInterval(-maxBackdating))
    }

    /// Ouvre la fenêtre d'arrêt, ou lève son ambiguïté si elle est déjà ouverte.
    ///
    /// L'heure ne bouge jamais une fois posée : la conduite a cessé au premier
    /// échantillon, et c'est cette heure-là qui datera la fin du trajet. Mais
    /// un « je marche » qui arrive après un « je ne bouge plus » apprend
    /// quelque chose — la personne est sortie — et raccourcit l'attente. Sans
    /// ça, se garer puis descendre de voiture trente secondes plus tard
    /// gardait la patience du cas ambigu alors que le doute était levé.
    ///
    /// L'inverse n'existe pas : une fois qu'on sait la personne sortie, un
    /// « immobile » qui suit ne le défait pas. Ce qui défait un arrêt, c'est un
    /// « en voiture », et il l'annule entièrement.
    private func noteStop(at date: Date, reason: StopReason) {
        guard let pending = pendingStop else {
            pendingStop = PendingStop(since: date, reason: reason)
            detectionLog.record(
                "Driving stopped — ending the trip in \(Int(Self.stopWindow(for: reason)))s unless it resumes."
            )
            return
        }
        guard case .ambiguous = pending.reason, case .leftTheVehicle = reason else { return }
        pendingStop = PendingStop(since: pending.since, reason: reason)
        detectionLog.record("The driver has left the vehicle — shortening the stop window.")
    }

    /// Decides what to do with a trip whose driving activity has stopped.
    /// Runs both on each new activity sample and from a timer, because a
    /// stopped phone may never produce another sample: without the timer a
    /// trip could stay open — GPS running — indefinitely.
    ///
    /// Une seule fenêtre commande les deux issues, garder ou jeter. C'étaient
    /// deux durées distinctes, et la plus courte des deux — soixante secondes
    /// avant de jeter — s'est révélée fausse le jour où la validation est
    /// passée à la distance : un bouchon parcouru sur cent mètres n'atteint
    /// pas le seuil, et se serait fait effacer au bout d'une minute d'arrêt.
    /// La question « la conduite a-t-elle vraiment cessé ? » est pourtant la
    /// même dans les deux cas ; seul ce qu'on en fait ensuite diffère.
    private func evaluatePendingDecision() {
        guard recordingStartedAt != nil,
              let stop = pendingStop,
              tripRecorder.isRecording
        else {
            return
        }

        let stoppedFor = Date().timeIntervalSince(stop.since)
        let window = Self.stopWindow(for: stop.reason)
        guard stoppedFor >= window else {
            scheduleDecision(after: window - stoppedFor)
            return
        }

        // La conduite a cessé, que le trajet soit gardé ou jeté ensuite : c'est
        // ici qu'on retient l'heure, et non dans `finalizeTrip`, pour couvrir
        // les deux issues d'un seul geste. Sans elle, le réveil suivant
        // retrouverait dans l'historique de Core Motion les échantillons mêmes
        // qui viennent de clore ce trajet et en rouvrirait un sur une voiture
        // garée. Voir `lastDrivingEndedAt`.
        lastDrivingEndedAt = stop.since

        // Relue maintenant, et non figée à l'ouverture de la fenêtre : un
        // trajet peut avoir franchi le seuil entre-temps, la conduite ayant
        // repris sans que l'app le voie passer.
        let distance = tripRecorder.currentDistanceMeters
        guard distance >= TripRecorder.minimumAutomaticTripDistance else {
            detectionLog.record(
                "Discarding an automatic trip: \(Int(distance))m covered, under the \(Int(TripRecorder.minimumAutomaticTripDistance))m floor."
            )
            tripRecorder.discard()
            resetState()
            return
        }

        finalizeTrip(endDate: stop.since)
    }

    private func scheduleDecision(after delay: TimeInterval) {
        pendingDecisionTask?.cancel()
        pendingDecisionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(delay, 1)))
            guard !Task.isCancelled else { return }
            self?.evaluatePendingDecision()
        }
    }

    private func clearPendingDecision() {
        pendingDecisionTask?.cancel()
        pendingDecisionTask = nil
        pendingStop = nil
    }

    /// `confirmed` dit si la conduite est établie ou seulement soupçonnée ;
    /// dans le second cas le trajet part en probation. `drivingSince` date le
    /// trajet, et n'est pas l'instant de cet appel — voir `maxBackdating`.
    private func startProvisionalTrip(confirmed: Bool, drivingSince: Date) {
        // Un échantillon de mouvement peut arriver dans l'intervalle entre la
        // perte d'accès et l'arrêt effectif de la surveillance.
        guard hasRecordingAccess else { return }

        let vehicle = vehicleService.selectedVehicle(in: modelContext)
        tripRecorder.start(vehicle: vehicle, source: .automatic, startDate: drivingSince)
        // Recording can refuse to start (location authorization lost since
        // monitoring was armed); claiming ownership of a trip that doesn't
        // exist would leave this detector waiting on it forever.
        guard tripRecorder.isRecording else { return }

        recordingStartedAt = Date()
        isDrivingConfirmed = confirmed
        clearPendingDecision()
        armDrivingRecheck()

        if confirmed {
            detectionLog.record("Driving detected — recording.")
        } else {
            detectionLog.record(
                "Driving suspected — recording on probation for \(Int(Self.probationWindow))s."
            )
            armProbation()
        }
    }

    /// La conduite est établie : le trajet cesse d'être à l'essai et suivra
    /// désormais le chemin ordinaire — fenêtre d'arrêt, seuil des 300 m,
    /// confirmation. Sans effet s'il l'était déjà.
    private func confirmDriving() {
        // `ownsTripInProgress` d'abord : un échantillon automobile arrive aussi
        // pendant un trajet lancé à la main, qui n'appartient pas à ce
        // détecteur et n'a aucune probation à lever.
        guard ownsTripInProgress, !isDrivingConfirmed else { return }
        isDrivingConfirmed = true
        probationTask?.cancel()
        probationTask = nil
        detectionLog.record("The suspected drive is confirmed — keeping the trip.")
    }

    private func armProbation() {
        probationTask?.cancel()
        probationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.probationWindow))
            guard !Task.isCancelled, let self else { return }
            endProbation()
        }
    }

    /// L'échéance est là : ou bien la trace prouve la conduite, ou bien le
    /// trajet n'a jamais existé.
    ///
    /// La distance est la preuve, et non un nouvel échantillon de Core Motion :
    /// `recentDriving` écarte les échantillons peu sûrs
    /// (`MotionActivityService.recentDriving`), donc celui qui a ouvert ce
    /// trajet-ci n'y figurera jamais. Ce que le GPS a mesuré, lui, est un fait.
    private func endProbation() {
        probationTask = nil
        guard ownsTripInProgress, !isDrivingConfirmed else { return }

        let distance = tripRecorder.currentDistanceMeters
        let peak = tripRecorder.maxObservedSpeed
        guard distance < TripRecorder.minimumAutomaticTripDistance else {
            detectionLog.record(
                "\(Int(distance))m covered on a suspected drive — that is a drive, keeping the trip."
            )
            isDrivingConfirmed = true
            return
        }

        // La distance n'est pas la seule preuve, et ce n'est pas la bonne pour
        // un départ retenu. Sortir d'un parking, attendre un feu de
        // quatre-vingt-dix secondes puis repartir, c'est cinquante mètres en
        // deux minutes : les 300 m effaçaient là un trajet parfaitement réel,
        // et l'effaçaient sans un mot. Une vitesse instantanée, elle, tranche
        // tout de suite — personne ne marche à trente kilomètres-heure — et il
        // suffit de l'avoir touchée une fois.
        //
        // Le seuil des 300 m reste entier ailleurs : dans
        // `evaluatePendingDecision` il ne demande pas « est-ce un véhicule ? »
        // mais « ce trajet vaut-il d'être enregistré ? », et une manœuvre de
        // stationnement à trente kilomètres-heure reste une manœuvre de
        // stationnement.
        guard peak < Self.confirmingSpeed else {
            detectionLog.record(
                "Only \(Int(distance))m covered, but \(Int(peak * 3.6))km/h was measured — that is a vehicle, keeping the trip."
            )
            isDrivingConfirmed = true
            return
        }

        detectionLog.record(
            "Discarding a suspected drive: \(Int(distance))m and \(Int(peak * 3.6))km/h peak in \(Int(Self.probationWindow))s."
        )
        tripRecorder.discard()
        resetState()
    }

    /// Relit l'activité de Core Motion à intervalle régulier tant qu'un trajet
    /// est en cours. Voir `drivingRecheckInterval` pour ce qu'il corrige.
    private func armDrivingRecheck() {
        drivingRecheckTask?.cancel()
        drivingRecheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.drivingRecheckInterval)
                guard !Task.isCancelled, let self else { return }
                await recheckDriving()
            }
        }
    }

    /// Confronte l'état du trajet à ce que Core Motion a réellement enregistré.
    ///
    /// Deux corrections, symétriques :
    ///
    /// - on roule encore, mais un arrêt est en attente : l'échantillon qui l'a
    ///   ouvert est dépassé — un feu rouge, une reprise que l'app suspendue n'a
    ///   pas vue. L'annuler évite de couper le trajet, et le GPS avec lui, en
    ///   pleine route.
    /// - on ne roule plus, et rien n'est en attente : aucun échantillon n'est
    ///   venu le dire. Ouvrir la fenêtre d'arrêt maintenant, au moment où la
    ///   conduite a vraiment cessé et non maintenant, évite de laisser le GPS
    ///   tourner jusqu'au prochain réveil — et de facturer le trajet jusque-là.
    private func recheckDriving() async {
        guard ownsTripInProgress, let startedAt = recordingStartedAt else { return }

        // On remonte jusqu'au début du trajet, et non sur une fenêtre fixe : la
        // bascule qu'on cherche a forcément eu lieu après lui, et l'app a pu
        // rester suspendue longtemps entre-temps. Sur cinq minutes glissantes,
        // un arrêt vieux d'un quart d'heure sortait de la fenêtre : la lecture
        // ne trouvait plus rien d'automobile dedans et datait la fin du trajet
        // du bord de la fenêtre — dix minutes de stationnement comptées comme
        // de la route. La requête reste bon marché, Core Motion n'enregistrant
        // que des changements.
        let lookback = max(Self.recentActivityLookback, Date().timeIntervalSince(startedAt))
        let reading = await motionActivityService.recentDriving(lookingBack: lookback)
        // Conditions can have changed while the query was in flight.
        guard ownsTripInProgress else { return }

        if reading.isAutomotive {
            // Une lecture d'historique ne porte que des échantillons sûrs :
            // elle tranche donc aussi la probation, sans attendre son échéance.
            confirmDriving()
            guard pendingStop != nil else { return }
            detectionLog.record("Core Motion still reads automotive — cancelling the pending stop.")
            clearPendingDecision()
            return
        }

        // Rien d'exploitable dans la fenêtre : Core Motion n'a rien à dire, et
        // deviner à sa place fermerait un trajet bien vivant.
        guard let stoppedAt = reading.stoppedAt else { return }
        // Jamais avant le début du trajet : un arrêt daté d'avant ferait une
        // durée négative, et `finalize` ne garderait pas un seul point.
        noteStop(
            at: max(stoppedAt, recordingStartedAt ?? stoppedAt),
            reason: StopReason(isMovingUnderOwnPower: reading.isMovingUnderOwnPower)
        )
        evaluatePendingDecision()
    }

    private func finalizeTrip(endDate: Date) {
        // A trip without a single GPS point has no route and no distance —
        // permission revoked mid-trip, or no signal the whole way. There is
        // nothing to show or confirm, so drop it rather than asking the user
        // about a 0 km trip.
        guard tripRecorder.hasRecordedRoutePoints else {
            detectionLog.record("Discarding an automatic trip that recorded no GPS point.")
            tripRecorder.discard()
            resetState()
            return
        }

        if let trip = tripRecorder.finalize(endDate: endDate) {
            if requiresTripConfirmation {
                notificationService.scheduleTripConfirmationNotification(for: trip)
            } else {
                trip.confirmationStatus = .confirmed
                modelContext.saveOrLog()
            }
        }
        resetState()
    }
}
