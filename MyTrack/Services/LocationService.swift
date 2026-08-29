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
        manager.startUpdatingLocation()
        return true
    }

    func stopActiveTracking() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where isAcceptable(location) {
            onLocationUpdate?(location)
        }
    }

    private func isAcceptable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return false }
        guard abs(location.timestamp.timeIntervalSinceNow) <= 5 else { return false }
        return true
    }
}
