//
//  LocationService.swift
//  MyTrack
//
//  Thin wrapper around CLLocationManager. Only handles GPS-signal-level
//  concerns (authorization, accuracy/staleness filtering) — trip-level
//  concerns (distance accumulation, speed sanity-checking) live in
//  TripRecorder, which is the only consumer of onLocationUpdate.
//

import Foundation
import OSLog
import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Depuis quand le suivi actif tourne — l'unique repère qui permette de
    /// reconnaître un point réellement périmé. Voir `isAcceptable`.
    private var trackingStartedAt: Date?

    /// Ce qu'on accepte d'antériorité sur le démarrage du suivi.
    ///
    /// Un point porte l'heure de la mesure, pas celle de la livraison : la
    /// toute première position d'un trajet est presque toujours datée d'une
    /// poignée de secondes avant l'appel à `startUpdatingLocation`. Sans cette
    /// marge, le premier point — celui qui fixe le lieu de départ du trajet —
    /// serait jeté. Elle reste très en deçà de l'âge d'une position mise en
    /// cache, qui se compte en minutes ou en heures.
    private static let startupTolerance: TimeInterval = 30

    private(set) var authorizationStatus: CLAuthorizationStatus

    var onLocationUpdate: ((CLLocation) -> Void)?

    /// Fires whenever the system reports an authorization change, including the
    /// initial one at launch. DrivingDetector uses it to arm (or stay off) as
    /// soon as "Always" is granted or revoked from Settings.
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// Fait apparaître la première des deux fenêtres : « Lorsque l'app est
    /// active ». Sans effet une fois la question posée, ou si l'app n'est pas
    /// au premier plan.
    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Fait apparaître la seconde fenêtre, celle du passage à « Toujours ».
    ///
    /// iOS ne l'accorde qu'à une app qui a **déjà** « Lorsque l'app est
    /// active » et qui n'a **jamais** demandé « Toujours » auparavant — une
    /// fois par installation, et une seule (c'est écrit noir sur blanc dans
    /// `CLLocationManager.h`).
    ///
    /// Appelée avant que « Lorsque l'app est active » soit accordé, elle
    /// n'échoue pas : elle montre exactement la même fenêtre que
    /// `requestWhenInUseAuthorization()` — iOS n'y propose jamais
    /// « Toujours » — mais dépense au passage ce coup unique. Tout appel
    /// suivant ne fait alors plus rien du tout, sans erreur ni rappel, et
    /// l'app reste sur « Lorsque l'app est active » sans que rien ne
    /// l'explique. C'est `DrivingDetector` qui enchaîne les deux fenêtres
    /// dans le bon ordre.
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Returns false when location isn't authorized, so the caller can avoid
    /// recording a trip that could never receive a single point — authorization
    /// can be revoked from Settings long after a recording path was set up.
    @discardableResult
    func startActiveTracking() -> Bool {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            AppLog.recording.error("GPS tracking not started: location isn't authorized.")
            return false
        }

        // Vrai dans les deux niveaux d'autorisation, et pas seulement pour
        // « Toujours ».
        //
        // Ce qui fait lever une exception ici, c'est l'absence du mode d'arrière-
        // plan `location` dans l'Info.plist, pas le niveau d'autorisation — et
        // ce mode est déclaré. « Lorsque l'app est active » autorise bien la
        // poursuite en arrière-plan dès lors qu'on la demande : iOS l'accorde et
        // montre son indicateur bleu pendant toute sa durée.
        //
        // Sans ça, un trajet lancé à la main avec « Lorsque l'app est active » —
        // le niveau que demande précisément le bouton Démarrer — cessait de
        // recevoir le moindre point dès que l'écran se verrouillait, ce que
        // personne ne manque de faire en conduisant. Le chronomètre continuait
        // de tourner, lui, puisqu'il compte l'heure murale : au retour, une
        // demi-heure de trajet affichait deux cents mètres.
        manager.allowsBackgroundLocationUpdates = true
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        trackingStartedAt = Date()
        manager.startUpdatingLocation()
        return true
    }

    func stopActiveTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        trackingStartedAt = nil
    }

    /// Low-power baseline used while auto-detection is enabled but no trip is
    /// active: wakes the app (even after the system has fully terminated it —
    /// though not after the user force-quits it) on a significant location
    /// change, so Core Motion gets a chance to notice driving has started.
    func startSignificantLocationMonitoring() {
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopSignificantLocationMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        onAuthorizationChange?(authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.recording.error("Location manager failed: \(error.localizedDescription, privacy: .public)")
    }

    /// CoreLocation ne livre pas un point à la fois : `locations` est un paquet,
    /// rangé du plus ancien au plus récent. Au premier plan il n'en contient
    /// presque toujours qu'un, parce que l'app tourne en continu et que le
    /// système la réveille à chaque mesure. Écran verrouillé, il en contient
    /// des dizaines : iOS regroupe les livraisons pour économiser la batterie
    /// et vide le paquet quand il redonne du temps à l'app.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        var accepted = 0
        for location in locations where isAcceptable(location) {
            accepted += 1
            onLocationUpdate?(location)
        }

        // Une ligne par livraison, pas par point : de quoi lire dans la Console
        // ce que l'arrière-plan reçoit vraiment. Un paquet de plusieurs points
        // dont le plus ancien a dix ou trente secondes, c'est le regroupement
        // à l'œuvre — le comportement normal, pas une anomalie.
        if let oldest = locations.first {
            let age = Int(-oldest.timestamp.timeIntervalSinceNow)
            AppLog.recording.debug(
                "Location delivery: \(locations.count) point(s), \(accepted) kept, oldest \(age)s old."
            )
        }
    }

    /// Filtre de qualité du signal — et rien d'autre.
    ///
    /// Il rejetait aussi tout point livré plus de 5 secondes après sa mesure.
    /// L'intention était bonne (écarter la position en cache que
    /// `startUpdatingLocation` livre d'emblée, qui peut dater d'heures et d'un
    /// autre endroit) mais le critère mesurait la mauvaise chose : l'écart à
    /// *maintenant*, c'est-à-dire le retard de livraison, pas la péremption du
    /// point.
    ///
    /// Au premier plan les deux se confondent, chaque point étant livré dans la
    /// seconde : la trace était donc parfaite. En arrière-plan, où le système
    /// livre par paquets, tous les points sauf le dernier avaient plus de 5
    /// secondes et étaient jetés — et un paquet livré avec un peu de retard
    /// l'était en entier. D'où la ligne droite entre deux ouvertures de l'app :
    /// seuls les points reçus au premier plan survivaient au filtre.
    ///
    /// Un point n'est réellement périmé que s'il précède le début du suivi. Son
    /// retard de livraison, lui, ne dit rien de sa validité : il est daté, et
    /// c'est cette date que la trace utilise.
    private func isAcceptable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return false }
        // Pas de suivi actif : ce qui arrive ici vient de la surveillance des
        // changements significatifs, qui n'alimente pas de trajet.
        guard let startedAt = trackingStartedAt else { return false }
        guard location.timestamp >= startedAt.addingTimeInterval(-Self.startupTolerance) else { return false }
        return true
    }
}
