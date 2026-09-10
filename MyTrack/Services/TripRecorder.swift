//
//  TripRecorder.swift
//  MyTrack
//
//  Shared recording engine: the only component that starts/stops active
//  GPS tracking. Both manual mode (RecordTripViewModel) and automatic mode
//  (DrivingDetector) drive this instead of touching CLLocationManager
//  themselves, so there is a single place where a trip is actually recorded.
//

import Foundation
import OSLog
import CoreLocation
import SwiftData
import Observation

@Observable
final class TripRecorder {
    private let locationService: LocationService
    private let detectionLog: DetectionLog
    private let modelContext: ModelContext

    private(set) var isRecording = false
    private(set) var currentDistanceMeters: Double = 0
    private(set) var currentStartDate: Date?

    /// La plus haute vitesse Doppler sûre observée depuis le début du trajet,
    /// en m/s. Zéro tant qu'aucun point n'en a porté.
    ///
    /// C'est la seconde preuve de la probation, et elle vaut mieux que la
    /// première. La distance parcourue demande 300 m en deux minutes, soit
    /// 9 km/h de moyenne : une sortie de parking suivie d'un feu long n'y
    /// arrive pas, et un vrai trajet urbain s'y faisait effacer. Avoir touché
    /// trente kilomètres-heure une seule fois, en revanche, est une chose
    /// qu'aucune marche ne produit — voir `DrivingDetector.endProbation`.
    ///
    /// Lue sur `location.speed` et jamais sur l'écart entre deux positions :
    /// c'est dans le second que vivent les aberrations du GPS, celles que
    /// `maxPlausibleSpeed` existe pour rejeter, et une seule d'entre elles
    /// suffirait à prouver une conduite qui n'a pas eu lieu. La vitesse
    /// Doppler est mesurée, elle porte sa propre incertitude, et c'est la
    /// borne basse de l'estimation qu'on retient : trente kilomètres-heure à
    /// vingt-cinq près ne prouve rien.
    private(set) var maxObservedSpeed: CLLocationSpeed = 0

    private var activeTrip: Trip?

    /// La dernière position **brute** retenue par les filtres.
    ///
    /// Brute, et c'est important : c'est la référence du contrôle de vitesse et
    /// du filtre d'immobilité, qui doivent juger la mesure et non ce qu'on en a
    /// fait. C'est aussi le point qui attend son voisin de droite pour être
    /// lissé — voir `smoothed`.
    private var lastAcceptedLocation: CLLocation?

    /// L'avant-dernière position brute : le voisin de gauche du lissage.
    /// Remise à `nil` après un ré-ancrage, pour ne pas lisser à travers un saut.
    private var previousRawLocation: CLLocation?

    /// Le dernier point réellement entré dans la trace, lissé. La distance
    /// s'accumule entre ceux-là et non entre les positions brutes : c'est ce
    /// qui fait que le chiffre affiché pendant la course et celui du trajet
    /// enregistré ne peuvent pas diverger.
    private var lastEmittedPoint: RoutePoint?

    /// Le parcours enregistré depuis le début du trajet, prêt à être tracé sur
    /// la carte de l'écran d'enregistrement.
    ///
    /// Tenu à part plutôt que relu sur `trip.routePoints`, pour deux raisons
    /// qui vont dans le même sens : ce dernier ne reçoit les points qu'aux
    /// points de contrôle, donc la trace n'avancerait que par bonds de quinze à
    /// soixante secondes ; et le relire à chaque nouveau point décoderait le
    /// blob entier une fois par seconde — précisément ce que `writtenPointCount`
    /// existe pour éviter.
    ///
    /// Ce sont les points *émis*, donc lissés : la trace affichée pendant la
    /// course est exactement celle qui sera enregistrée, et non les positions
    /// brutes qu'elle corrige.
    private(set) var currentRouteCoordinates: [CLLocationCoordinate2D] = []

    /// La trace en cours, tenue en mémoire et recopiée dans le trajet aux
    /// points de contrôle seulement. Voir `flushRoutePoints`.
    private var bufferedPoints: [RoutePoint] = []
    private var lastCheckpointAt: Date?

    /// Combien de points la trace du trajet porte déjà. Tenu à part plutôt que
    /// lu sur `trip.routePoints.count`, qui décoderait le bloc entier — le coût
    /// même que l'intervalle adaptatif cherche à éviter.
    private var writtenPointCount = 0

    /// Combien de points d'affilée le contrôle de vitesse vient de refuser.
    /// Voir `maxConsecutiveRejections`.
    private var consecutiveRejections = 0

    /// Tous les combien la trace descend sur le disque.
    ///
    /// En secondes et non en points, depuis que le GPS livre une mesure par
    /// seconde : « tous les dix points » voulait dire dix secondes en ville et
    /// dix secondes sur l'autoroute, mais plus rien du tout quand le signal
    /// s'espace. C'est ce que coûte au maximum une fin de trajet perdue si le
    /// système tue l'app en arrière-plan.
    private static let checkpointInterval: TimeInterval = 15

    /// Vers quoi cet intervalle s'allonge quand la trace devient longue, et le
    /// nombre de points au bout duquel il y est.
    ///
    /// `trip.routePoints` est un bloc unique (voir `checkpoint`) : chaque
    /// descente réécrit la trace *entière*, et coûte donc de plus en plus cher
    /// à mesure que le trajet avance. À intervalle fixe, deux heures de route
    /// font quatre cent quatre-vingts réécritures dont la dernière porte plus
    /// de sept mille points — des dizaines de mégaoctets écrits pour rien, sur
    /// le fil principal et en arrière-plan, là où le système compte le temps
    /// qu'on lui prend avant de tuer l'app.
    ///
    /// Ce qu'on allonge ici, c'est ce qu'on perd si l'app est tuée : on ne
    /// l'allonge donc que là où la réécriture le justifie, c'est-à-dire tard
    /// dans un long trajet. Un trajet ordinaire de vingt minutes n'atteint
    /// jamais le seuil et garde ses quinze secondes.
    private static let maxCheckpointInterval: TimeInterval = 60
    private static let longRouteThreshold = 2000

    /// Non privée, comme `minimumAutomaticTripDistance` juste plus bas :
    /// `DrivingDetector` s'en sert pour borner la vitesse d'un point de veille,
    /// et un plafond de vraisemblance écrit deux fois finirait par diverger.
    static let maxPlausibleSpeed: CLLocationSpeed = 60 // m/s (~216 km/h) — rejects GPS glitches

    /// Le plus grand intervalle à travers lequel on accepte de lisser.
    ///
    /// Le lissage suppose que les trois points décrivent un mouvement continu.
    /// Quand le flux se troue — le GPS perd le signal sous un pont, l'app est
    /// suspendue — les deux voisins peuvent encadrer un virage entier, et tirer
    /// le point du milieu vers la corde couperait la route au lieu de la
    /// débruiter. Six secondes : six fois le rythme normal, et bien en deçà du
    /// plus court trou qui puisse cacher une manœuvre.
    private static let maxSmoothingSpan: TimeInterval = 6

    /// De combien la trace *enregistrée* a le droit de s'écarter de la trace
    /// *mesurée*, une fois le trajet fini. Voir `RoutePoint.simplified`.
    ///
    /// Quatre mètres, soit vingt-cinq fois moins que l'imprécision qu'un point
    /// a le droit de porter (`LocationService.maxHorizontalAccuracy`), et moins
    /// que la largeur d'une voie : ce qu'on retire est très en deçà du bruit
    /// que la trace contient déjà, donc invisible sur la carte.
    ///
    /// Ce que ça retire, mesuré : une ligne droite tombe à ses deux extrémités
    /// et un angle de rue à son seul coin, mais le gain d'ensemble dépend du
    /// bruit du signal. Sur une heure d'autoroute simulée avec le bruit d'un
    /// téléphone en poche (±4 m), 3 600 points tombent à un millier — trois
    /// fois moins ; sur un signal propre, dix fois moins. Ne pas monter au-delà
    /// « pour faire mieux » : à huit mètres la trace commence à couper les
    /// angles de rue visiblement.
    private static let simplificationTolerance: CLLocationDistance = 4

    /// En deçà de quoi un trajet détecté automatiquement n'est pas une course.
    ///
    /// C'était une durée — « avoir roulé plus de soixante secondes » — et la
    /// durée mesurait la mauvaise chose. Elle se trompait des deux côtés :
    /// aller chercher le pain à six cents mètres prend quarante secondes et
    /// était effacé sans un mot, tandis qu'attendre quelqu'un moteur tournant
    /// donne « en voiture » pendant dix minutes et zéro mètre, et passait la
    /// barre haut la main. La distance, elle, *est* la question posée — et
    /// depuis que la trace vaut quelque chose, elle est mesurée juste.
    ///
    /// Trois cents mètres écartent les manœuvres de stationnement et les
    /// faux positifs de Core Motion sans écarter la moindre course réelle.
    /// Ce qu'aucun seuil ne saura filtrer, c'est le bus et le train, que Core
    /// Motion annonce eux aussi « en voiture » : c'est le travail de la
    /// confirmation, pas d'un nombre.
    ///
    /// Ici plutôt que dans `DrivingDetector` parce que deux chemins s'en
    /// servent : la décision en direct, et le ménage des trajets orphelins
    /// ci-dessous — un processus tué en pleine course n'a plus de détecteur
    /// pour trancher à sa place, et doit trancher pareil.
    static let minimumAutomaticTripDistance: CLLocationDistance = 300

    /// En deçà de quoi un point n'apporte rien à la trace.
    ///
    /// `LocationService` n'impose plus de filtre de distance à CoreLocation —
    /// c'était lui qui trouait la trace — mais ce filtre rendait un service au
    /// passage : il empêchait la trace d'avancer quand la voiture, elle,
    /// n'avançait pas. Une mesure par seconde à ±5 m, arrêté à un feu, c'est
    /// deux ou trois mètres de gigue par point : quelques centaines de mètres
    /// pour un embouteillage, ajoutés à une note de frais kilométriques.
    ///
    /// Le filtre revient donc ici, là où il ne coûte rien : il choisit ce qu'on
    /// *garde*, et non ce qu'iOS *mesure*. À 50 km/h il ne retire pas un seul
    /// point — une seconde en fait quatorze — et il n'agit qu'au pas.
    private static let minimumDistanceBetweenPoints: CLLocationDistance = 5

    /// La vitesse en dessous de laquelle l'appareil est réputé à l'arrêt.
    ///
    /// `CLLocation.speed` vient de l'effet Doppler et vaut -1 quand elle est
    /// inconnue ; connue, elle est bien plus sûre que l'écart entre deux
    /// positions elles-mêmes bruitées, et c'est elle qui repère l'arrêt quand
    /// la gigue dépasse le seuil de distance ci-dessus.
    private static let stationarySpeed: CLLocationSpeed = 0.5

    /// Au-delà de ce silence, le point est gardé même immobile.
    ///
    /// C'est le garde-fou des deux filtres ci-dessus : ils décident de *ne pas*
    /// enregistrer, et rien, dans une app dont c'est tout le métier, ne doit
    /// pouvoir décider ça indéfiniment. Un capteur qui rendrait une vitesse
    /// Doppler nulle à tort suffirait sinon à effacer un trajet entier sans
    /// qu'une seule ligne le dise.
    ///
    /// Une minute de trajet à l'arrêt coûte alors soixante points de gigue,
    /// soit quelques mètres — sans commune mesure avec ce que le filtre évite.
    private static let maxSilenceWhileStandingStill: TimeInterval = 60

    /// Au bout de combien de refus consécutifs on repart du point reçu plutôt
    /// que de continuer à le comparer au précédent.
    ///
    /// Le contrôle de vitesse compare chaque point au dernier *accepté* : un
    /// point aberrant est donc écarté sans jamais devenir la référence, ce qui
    /// est exactement ce qu'on veut — sauf si c'est la référence elle-même qui
    /// est fausse. Une mesure datée de trente secondes dans le futur, et tout
    /// ce qui suit se retrouve « avant » elle et part au rebut : la trace
    /// s'arrête là, en silence, jusqu'à la fin du trajet.
    ///
    /// Cinq refus d'affilée — cinq secondes — ne sont plus un point aberrant,
    /// c'est une référence à changer. La distance du saut, elle, n'est pas
    /// comptée : on reprend la trace, on n'invente pas les kilomètres qui
    /// manquent.
    private static let maxConsecutiveRejections = 5

    /// Whether the trip in progress has at least one accepted GPS point.
    /// A trip that has none would be saved as an empty 0 km route.
    var hasRecordedRoutePoints: Bool { lastAcceptedLocation != nil }

    init(locationService: LocationService, detectionLog: DetectionLog, modelContext: ModelContext) {
        self.locationService = locationService
        self.detectionLog = detectionLog
        self.modelContext = modelContext
    }

    /// Finds any trip left with `endDate == nil` by a previous process that
    /// died mid-recording (crash, or the system killing a backgrounded app)
    /// and closes it out instead of leaving it stuck "in progress" forever.
    /// An automatic trip that never covered `minimumAutomaticTripDistance` is
    /// discarded, matching what DrivingDetector would have done live; anything
    /// else (manual, or a real journey) is finalized at its last known point.
    func cleanUpOrphanedTrips() {
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil })
        guard let orphans = try? modelContext.fetch(descriptor) else { return }

        for trip in orphans {
            guard let lastPoint = trip.routePoints.last else {
                modelContext.delete(trip)
                continue
            }

            if trip.source == .automatic,
               Self.distance(over: trip.routePoints) < Self.minimumAutomaticTripDistance {
                modelContext.delete(trip)
            } else {
                trip.endDate = lastPoint.timestamp
                trip.endLatitude = lastPoint.latitude
                trip.endLongitude = lastPoint.longitude
            }
        }
        modelContext.saveOrLog()
    }

    /// Starts recording, unless location isn't authorized — in which case no
    /// Trip row is created at all, rather than leaving an empty one behind that
    /// could never receive a single point. Callers check `isRecording` to know.
    ///
    /// `startDate` date le trajet, et vaut par défaut l'instant de l'appel —
    /// ce que veut le mode manuel, où l'appui sur Démarrer *est* le début. La
    /// détection automatique, elle, est prévenue après coup : Core Motion date
    /// ses échantillons, et c'est cette date-là qu'elle passe ici, sans quoi le
    /// trajet commencerait à l'instant où l'app a été mise au courant.
    func start(vehicle: Vehicle?, source: TripSource, startDate: Date = .now) {
        guard !isRecording else { return }

        locationService.onLocationUpdate = { [weak self] location in
            self?.handle(location)
        }
        guard locationService.startActiveTracking() else {
            locationService.onLocationUpdate = nil
            return
        }

        let trip = Trip(startDate: startDate, source: source, vehicle: vehicle)
        modelContext.insert(trip)
        modelContext.saveOrLog()

        activeTrip = trip
        lastAcceptedLocation = nil
        previousRawLocation = nil
        lastEmittedPoint = nil
        currentRouteCoordinates = []
        bufferedPoints = []
        writtenPointCount = 0
        lastCheckpointAt = .now
        consecutiveRejections = 0
        currentDistanceMeters = 0
        maxObservedSpeed = 0
        currentStartDate = trip.startDate
        isRecording = true
    }

    /// Stops tracking and deletes the in-progress trip entirely — used when
    /// DrivingDetector decides an automatic trip was too short to be real.
    func discard() {
        guard let trip = activeTrip else { return }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil
        modelContext.delete(trip)
        modelContext.saveOrLog()
        resetState()
    }

    /// Ends the trip normally and saves it. Source-agnostic: manual mode calls
    /// this directly with `.now`; DrivingDetector calls it with the moment
    /// driving actually stopped (not when the stop-confirmation window ends).
    /// Returns the finalized trip so DrivingDetector can schedule a
    /// confirmation notification for it.
    ///
    /// La trace est ramenée à la fenêtre du trajet, et la distance recalculée
    /// dessus. C'est tout l'écart entre les deux appelants : le mode manuel
    /// termine à `.now`, donc rien n'est retiré, tandis que la détection
    /// automatique termine au moment où la conduite s'est arrêtée — une à trois
    /// minutes avant, le temps de la fenêtre de confirmation d'arrêt, pendant
    /// laquelle le GPS tournait encore. Les points de ces cinq minutes-là étaient comptés
    /// dans la distance sans l'être dans la durée : trois cents mètres à pied
    /// entre la voiture et le bureau s'ajoutaient à chaque trajet, et un rapport
    /// de frais kilométriques les facturait.
    @discardableResult
    func finalize(endDate: Date) -> Trip? {
        guard let trip = activeTrip else { return nil }
        locationService.stopActiveTracking()
        locationService.onLocationUpdate = nil

        // Le point qui attendait son voisin de droite ne l'aura jamais : il
        // entre tel quel, non lissé. Sans ça, la dernière seconde du trajet —
        // et le lieu d'arrivée avec elle — resterait dehors.
        if let pending = lastAcceptedLocation {
            appendToRoute(Self.point(from: pending), into: trip)
            lastAcceptedLocation = nil
        }

        // Ce que le dernier point de contrôle n'a pas encore descendu : sans
        // ça, la fin du trajet — jusqu'à quinze secondes de route — resterait
        // en mémoire et disparaîtrait avec elle.
        flushRoutePoints(into: trip)

        let recorded = trip.routePoints.filter { $0.timestamp <= endDate }

        // Rien avant la fin de la conduite : le GPS n'avait rien accroché de la
        // course elle-même. Il n'y a ni trace ni distance à garder, et un trajet
        // de zéro kilomètre n'a rien à faire dans une liste — même raison que la
        // garde de `DrivingDetector.finalizeTrip`.
        guard let last = recorded.last else {
            modelContext.delete(trip)
            modelContext.saveOrLog()
            resetState()
            return nil
        }

        // La distance se mesure sur la trace complète, et *avant* de
        // l'alléger : la simplification coupe les virages de quelques mètres
        // chacun, et mesurer après raccourcirait le trajet d'autant. Une note
        // de frais kilométriques facture cet écart-là.
        //
        // Complète, mais déjà lissée : le débruitage a eu lieu point par point
        // à l'enregistrement (voir `smoothed`), et c'est délibérément l'inverse
        // de la simplification. L'un corrige la mesure et doit donc précéder le
        // calcul, l'autre allège l'affichage et doit donc le suivre.
        trip.endDate = endDate
        trip.distanceMeters = Self.distance(over: recorded)
        let simplified = RoutePoint.simplified(recorded, tolerance: Self.simplificationTolerance)
        trip.routePoints = simplified
        trip.endLatitude = last.latitude
        trip.endLongitude = last.longitude
        modelContext.saveOrLog()

        // Le premier chiffre dit d'un coup d'œil si la trace est dense ou
        // trouée : une mesure par seconde est le régime attendu, donc une
        // centaine de points pour deux minutes, un bon millier pour vingt. Le
        // second est ce qu'il en reste une fois la trace allégée, et se lit
        // comme un rapport au premier, jamais à la durée.
        let duration = Int(endDate.timeIntervalSince(trip.startDate))
        detectionLog.record(
            "Trip finalized: \(recorded.count) GPS point(s) over \(duration)s, \(simplified.count) kept, \(Int(trip.distanceMeters))m."
        )

        resetState()
        return trip
    }

    /// La longueur d'une trace, point à point.
    ///
    /// Le même calcul que celui qu'accumule `handle(_:)` — `CLLocation.distance`
    /// sur des points consécutifs — donc le même résultat quand rien n'est
    /// retiré : la distance enregistrée ne saute pas par rapport à celle qui
    /// s'affichait pendant la course.
    private static func distance(over points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            let from = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let to = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            let leg = from.distance(from: to)
            // Le saut d'un ré-ancrage : il figure dans la trace, parce qu'il
            // faut bien relier ses deux moitiés, mais personne ne l'a parcouru.
            // Mot pour mot la règle de `appendToRoute`, qui tient le compteur
            // affiché pendant la course : les deux chiffres portent sur la même
            // trace et l'écartent pareil, donc ils ne peuvent pas diverger.
            // Voir `maxConsecutiveRejections`.
            let elapsed = pair.1.timestamp.timeIntervalSince(pair.0.timestamp)
            guard elapsed > 0, leg / elapsed <= maxPlausibleSpeed else { return total }
            return total + leg
        }
    }

    /// Vrai quand le nouveau point ne décrit qu'un appareil immobile.
    /// Voir `minimumDistanceBetweenPoints` et `stationarySpeed`.
    private static func isStandingStill(_ location: CLLocation, from last: CLLocation) -> Bool {
        if location.speed >= 0, location.speed < stationarySpeed { return true }
        return last.distance(from: location) < minimumDistanceBetweenPoints
    }

    private func resetState() {
        activeTrip = nil
        lastAcceptedLocation = nil
        previousRawLocation = nil
        lastEmittedPoint = nil
        currentRouteCoordinates = []
        bufferedPoints = []
        writtenPointCount = 0
        lastCheckpointAt = nil
        consecutiveRejections = 0
        currentDistanceMeters = 0
        maxObservedSpeed = 0
        currentStartDate = nil
        isRecording = false
    }

    private func handle(_ location: CLLocation) {
        guard let trip = activeTrip else { return }

        // Relevée ici, avant tout le reste : les filtres qui suivent renvoient
        // tôt sur un point immobile ou hors séquence, et un point qui n'apporte
        // rien à la trace porte quand même la mesure qui prouve qu'on est dans
        // un véhicule. Voir `maxObservedSpeed`.
        let dopplerFloor = location.speed - location.speedAccuracy
        if location.speed >= 0, location.speedAccuracy >= 0, dopplerFloor <= Self.maxPlausibleSpeed {
            maxObservedSpeed = max(maxObservedSpeed, max(dopplerFloor, 0))
        }

        // Vrai quand on reprend la trace sur un point que le contrôle de
        // vitesse refuse encore, faute d'une meilleure référence : le point
        // entre dans la trace, mais le saut qui y mène n'entre pas dans la
        // distance. Voir `maxConsecutiveRejections`.
        var isReanchoring = false

        if let last = lastAcceptedLocation {
            // A point that isn't strictly newer than the last accepted one is a
            // duplicate or an out-of-order delivery: it can't be speed-checked,
            // so it's dropped rather than let through unchecked.
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            guard elapsed > 0 else { return }
            if last.distance(from: location) / elapsed > Self.maxPlausibleSpeed {
                consecutiveRejections += 1
                guard consecutiveRejections >= Self.maxConsecutiveRejections else { return }
                AppLog.recording.error(
                    "\(Self.maxConsecutiveRejections) implausible points in a row — re-anchoring the route on the latest one."
                )
                isReanchoring = true
            }
            consecutiveRejections = 0

            // Rien n'a bougé : ni la trace ni la distance n'ont à avancer.
            if !isReanchoring,
               elapsed < Self.maxSilenceWhileStandingStill,
               Self.isStandingStill(location, from: last) {
                return
            }
        }

        // Le point brut est retenu. Ce qui entre dans la trace, en revanche,
        // c'est le point *précédent* : il vient d'acquérir son voisin de
        // droite, donc il peut enfin être lissé. La trace a ainsi un point — une
        // seconde — de retard sur la mesure, ce qui ne se voit nulle part.
        if let pending = lastAcceptedLocation {
            if isReanchoring {
                // Les deux moitiés d'un ré-ancrage ne décrivent pas le même
                // endroit : lisser à travers le saut inventerait un chemin
                // entre les deux.
                appendToRoute(Self.point(from: pending), into: trip)
                previousRawLocation = nil
            } else {
                appendToRoute(
                    Self.smoothed(pending, between: previousRawLocation, and: location)
                        ?? Self.point(from: pending),
                    into: trip
                )
                previousRawLocation = pending
            }
        }

        lastAcceptedLocation = location

        checkpoint(trip)
    }

    /// Fait entrer un point dans la trace, et compte ce qu'il ajoute au trajet.
    ///
    /// La distance se mesure entre points **enregistrés**, jamais entre
    /// positions brutes, et c'est tout le sujet de `smoothed` : le bruit du GPS
    /// ne se contente pas de faire trembler la trace, il **allonge** chaque pas.
    /// Sur une simulation à une mesure par seconde avec un bruit de trois
    /// mètres — la ville ordinaire — la distance brute dépasse la vraie de huit
    /// pour cent ; à six mètres, en rues encaissées, de vingt-huit. Une note de
    /// frais kilométriques facture cet écart-là, et le facture en trop.
    ///
    /// Le segment invraisemblable est écarté selon la règle exacte de
    /// `distance(over:)` — le saut d'un ré-ancrage figure dans la trace, parce
    /// qu'il faut bien relier ses deux moitiés, mais personne ne l'a parcouru.
    /// Écrite ici sous la même forme que là-bas, les deux chiffres ne peuvent
    /// pas diverger : celui qui s'affiche pendant la course est calculé par ce
    /// chemin-ci, celui du trajet enregistré par l'autre.
    private func appendToRoute(_ point: RoutePoint, into trip: Trip) {
        if trip.startLatitude == nil {
            trip.startLatitude = point.latitude
            trip.startLongitude = point.longitude
        }

        if let last = lastEmittedPoint {
            let elapsed = point.timestamp.timeIntervalSince(last.timestamp)
            let leg = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            if elapsed > 0, leg / elapsed <= Self.maxPlausibleSpeed {
                currentDistanceMeters += leg
            }
        }

        bufferedPoints.append(point)
        lastEmittedPoint = point
        currentRouteCoordinates.append(
            CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        )
    }

    private static func point(from location: CLLocation) -> RoutePoint {
        RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp
        )
    }

    /// Le point `middle` ramené à mi-chemin de là où ses deux voisins le
    /// placeraient — le débruitage le plus léger qui vaille la peine.
    ///
    /// Ce n'est pas la même opération que `RoutePoint.simplified`, et l'ordre
    /// compte : le lissage corrige la mesure, la simplification allège ce qui
    /// en reste. Prises dans l'autre sens elles se contredisent, parce que
    /// Douglas-Peucker garde par construction les points qui s'écartent le plus
    /// de leur corde — c'est-à-dire, sur une trace bruitée, **les aberrations
    /// elles-mêmes**, en jetant les points alignés qui les noyaient. D'où
    /// l'impression, la simplification arrivée, d'une trace soudain couverte de
    /// dents alors qu'elles y étaient déjà : sur une trace mesurée, une passe
    /// de simplification faisait passer la proportion de points en saillie de
    /// vingt-sept à quatre-vingt-cinq pour cent.
    ///
    /// La moyenne est pondérée par le temps et non par le rang : quand un point
    /// manque, ses voisins ne l'encadrent plus symétriquement, et une moyenne
    /// à poids fixes le déplacerait le long de la route au lieu de le ramener
    /// dessus. À intervalles réguliers, la formule redonne exactement le
    /// classique un-deux-un.
    ///
    /// Une seule passe, et c'est un choix mesuré, pas un réglage par défaut.
    /// Elle ramène l'écart moyen à la route de 3,8 m à 2,9 m, la pire saillie
    /// de 18 m à 11 m, et l'erreur de distance de +8 % à +0,5 % ; sur une trace
    /// sans bruit, elle ne coupe que 0,28 % dans les virages — un rond-point
    /// complet compris, où elle *améliore* encore la fidélité. Une seconde
    /// passe gagnerait peu et raboterait deux fois plus les courbes serrées.
    private static func smoothed(
        _ middle: CLLocation, between previous: CLLocation?, and next: CLLocation
    ) -> RoutePoint? {
        guard let previous else { return nil }
        let span = next.timestamp.timeIntervalSince(previous.timestamp)
        guard span > 0, span <= Self.maxSmoothingSpan else { return nil }

        let fraction = middle.timestamp.timeIntervalSince(previous.timestamp) / span
        guard (0...1).contains(fraction) else { return nil }

        let predictedLatitude = previous.coordinate.latitude
            + (next.coordinate.latitude - previous.coordinate.latitude) * fraction
        let predictedLongitude = previous.coordinate.longitude
            + (next.coordinate.longitude - previous.coordinate.longitude) * fraction

        return RoutePoint(
            latitude: (middle.coordinate.latitude + predictedLatitude) / 2,
            longitude: (middle.coordinate.longitude + predictedLongitude) / 2,
            timestamp: middle.timestamp
        )
    }

    /// Recopie la trace en mémoire dans le trajet, et l'enregistre — pas plus
    /// souvent que `checkpointInterval`.
    ///
    /// Les points ne vont plus un par un dans `trip.routePoints`. C'est une
    /// propriété `Codable` de SwiftData, donc un bloc unique : chaque `append`
    /// relit et réécrit la trace *entière*. Tant qu'un trajet de vingt minutes
    /// tenait en dix points, ça ne se voyait pas ; à une mesure par seconde, il
    /// en compte plus de mille, et le coût devient celui d'un carré — sur le fil
    /// principal, en arrière-plan, là où le système compte le temps qu'on lui
    /// prend avant de tuer l'app. Le tampon en mémoire ramène chaque point à un
    /// `append` sur un tableau ordinaire, et la réécriture à une fois toutes les
    /// quinze secondes.
    private func checkpoint(_ trip: Trip) {
        let now = Date()
        guard now.timeIntervalSince(lastCheckpointAt ?? now) >= currentCheckpointInterval else { return }
        lastCheckpointAt = now
        flushRoutePoints(into: trip)
        modelContext.saveOrLog()
    }

    private func flushRoutePoints(into trip: Trip) {
        guard !bufferedPoints.isEmpty else { return }
        trip.routePoints.append(contentsOf: bufferedPoints)
        writtenPointCount += bufferedPoints.count
        bufferedPoints.removeAll(keepingCapacity: true)

        // La distance descend ici, et non à chaque point reçu.
        //
        // Elle y était assignée une fois par seconde, ce qui salissait le
        // `ModelContext` en continu sans que rien ne le lise : l'écran
        // d'enregistrement lit `currentDistanceMeters` sur ce service, qui est
        // `@Observable`, et `cleanUpOrphanedTrips` recalcule la sienne sur la
        // trace. Le modèle n'a donc besoin d'être juste qu'aux moments où il
        // est justement enregistré.
        trip.distanceMeters = currentDistanceMeters
    }

    /// L'intervalle du moment : `checkpointInterval` tant que la trace est
    /// courte, `maxCheckpointInterval` une fois `longRouteThreshold` franchi,
    /// et la ligne droite entre les deux.
    private var currentCheckpointInterval: TimeInterval {
        let ratio = min(Double(writtenPointCount) / Double(Self.longRouteThreshold), 1)
        return Self.checkpointInterval + ratio * (Self.maxCheckpointInterval - Self.checkpointInterval)
    }
}
