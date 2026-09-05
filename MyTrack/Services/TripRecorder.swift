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
    private let modelContext: ModelContext

    private(set) var isRecording = false
    private(set) var currentDistanceMeters: Double = 0
    private(set) var currentStartDate: Date?

    private var activeTrip: Trip?
    private var lastAcceptedLocation: CLLocation?

    /// La trace en cours, tenue en mémoire et recopiée dans le trajet aux
    /// points de contrôle seulement. Voir `flushRoutePoints`.
    private var bufferedPoints: [RoutePoint] = []
    private var lastCheckpointAt: Date?

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

    private static let maxPlausibleSpeed: CLLocationSpeed = 60 // m/s (~216 km/h) — rejects GPS glitches

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

    init(locationService: LocationService, modelContext: ModelContext) {
        self.locationService = locationService
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
    func start(vehicle: Vehicle?, source: TripSource) {
        guard !isRecording else { return }

        locationService.onLocationUpdate = { [weak self] location in
            self?.handle(location)
        }
        guard locationService.startActiveTracking() else {
            locationService.onLocationUpdate = nil
            return
        }

        let trip = Trip(startDate: .now, source: source, vehicle: vehicle)
        modelContext.insert(trip)
        modelContext.saveOrLog()

        activeTrip = trip
        lastAcceptedLocation = nil
        bufferedPoints = []
        lastCheckpointAt = .now
        consecutiveRejections = 0
        currentDistanceMeters = 0
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

        trip.endDate = endDate
        trip.routePoints = recorded
        trip.distanceMeters = Self.distance(over: recorded)
        trip.endLatitude = last.latitude
        trip.endLongitude = last.longitude
        modelContext.saveOrLog()

        // Le chiffre qui dit d'un coup d'œil si la trace est dense ou trouée.
        // Une mesure par seconde est le régime attendu : une centaine de points
        // pour deux minutes, un bon millier pour vingt.
        let duration = Int(endDate.timeIntervalSince(trip.startDate))
        AppLog.recording.notice(
            "Trip finalized: \(recorded.count) GPS point(s) over \(duration)s, \(Int(trip.distanceMeters))m."
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
            // La même règle qu'à l'enregistrement, sans quoi les deux distances
            // — celle qui s'affiche pendant la course et celle qui est
            // enregistrée — ne coïncideraient plus. Voir `maxConsecutiveRejections`.
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
        bufferedPoints = []
        lastCheckpointAt = nil
        consecutiveRejections = 0
        currentDistanceMeters = 0
        currentStartDate = nil
        isRecording = false
    }

    private func handle(_ location: CLLocation) {
        guard let trip = activeTrip else { return }

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

        if trip.startLatitude == nil {
            trip.startLatitude = location.coordinate.latitude
            trip.startLongitude = location.coordinate.longitude
        }

        if let last = lastAcceptedLocation, !isReanchoring {
            currentDistanceMeters += last.distance(from: location)
        }

        bufferedPoints.append(
            RoutePoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp
            )
        )
        trip.distanceMeters = currentDistanceMeters
        lastAcceptedLocation = location

        checkpoint(trip)
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
        guard now.timeIntervalSince(lastCheckpointAt ?? now) >= Self.checkpointInterval else { return }
        lastCheckpointAt = now
        flushRoutePoints(into: trip)
        modelContext.saveOrLog()
    }

    private func flushRoutePoints(into trip: Trip) {
        guard !bufferedPoints.isEmpty else { return }
        trip.routePoints.append(contentsOf: bufferedPoints)
        bufferedPoints.removeAll(keepingCapacity: true)
    }
}
