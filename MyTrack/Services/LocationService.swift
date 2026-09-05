//
//  LocationService.swift
//  MyTrack
//
//  Thin wrapper around CLLocationManager. Only handles GPS-signal-level
//  concerns (authorization, accuracy/staleness filtering, keeping the stream
//  running) — trip-level concerns (distance accumulation, speed
//  sanity-checking) live in TripRecorder, which is the only consumer of
//  onLocationUpdate.
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

    /// Quand CoreLocation a livré pour la dernière fois, quoi que ce soit — y
    /// compris des points que le filtre a ensuite jetés. C'est le repère du
    /// chien de garde : ce qu'il surveille, c'est le silence du flux, pas la
    /// qualité de ce qu'il transporte.
    private var lastDeliveryAt: Date?

    private var watchdogTask: Task<Void, Never>?

    /// La session d'activité en arrière-plan, tenue pendant toute la durée du
    /// suivi. Voir `startActiveTracking`.
    private var backgroundSession: CLBackgroundActivitySession?

    /// Ce qu'on accepte d'antériorité sur le démarrage du suivi.
    ///
    /// Un point porte l'heure de la mesure, pas celle de la livraison : la
    /// toute première position d'un trajet est presque toujours datée d'une
    /// poignée de secondes avant l'appel à `startUpdatingLocation`. Sans cette
    /// marge, le premier point — celui qui fixe le lieu de départ du trajet —
    /// serait jeté. Elle reste très en deçà de l'âge d'une position mise en
    /// cache, qui se compte en minutes ou en heures.
    private static let startupTolerance: TimeInterval = 30

    /// L'imprécision au-delà de laquelle un point ne décrit plus une route.
    ///
    /// Elle valait 50 m, et c'était la moitié de la trace en pointillé : au
    /// premier plan, écran allumé, l'iPhone donne des points à ±5 m et le
    /// seuil ne se voyait pas ; écran verrouillé, téléphone dans une poche ou
    /// un sac, dans une rue bordée d'immeubles ou sous la pluie, il tourne
    /// autour de ±30 à ±70 m. Le seuil jetait alors la majorité d'un trajet
    /// sans rien dire, et la carte reliait par une droite les deux rares
    /// points qui l'avaient passé.
    ///
    /// 100 m garde tout ce qui vient réellement du GPS, y compris dégradé —
    /// un point à ±70 m vaut infiniment mieux qu'un trait de deux kilomètres
    /// à travers champs — et rejette encore ce qui vient des antennes ou du
    /// Wi-Fi, qui se compte en centaines de mètres ou en kilomètres. Les
    /// aberrations qui passeraient quand même sont arrêtées plus loin, par le
    /// contrôle de vitesse de `TripRecorder`.
    private static let maxHorizontalAccuracy: CLLocationAccuracy = 100

    /// À quel rythme le chien de garde regarde, et à partir de quel silence il
    /// relance. Voir `restartIfStalled`.
    private static let watchdogPeriod: Duration = .seconds(10)
    private static let stallThreshold: TimeInterval = 20

    private(set) var authorizationStatus: CLAuthorizationStatus

    var onLocationUpdate: ((CLLocation) -> Void)?
    var onBackgroundWake: (() -> Void)?

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

        // « Position approximative » est une autorisation à part, que l'écran
        // des réglages d'iOS pose sous celle-ci et qu'on peut donc laisser
        // fermée en ayant tout accordé par ailleurs. Elle ne coupe rien : elle
        // remplace chaque point par un point à quelques kilomètres de là. Aucun
        // ne passera le filtre, le trajet finira sans trace, et rien dans
        // l'app ne l'expliquerait sans cette ligne.
        if manager.accuracyAuthorization == .reducedAccuracy {
            AppLog.recording.error(
                "Precise Location is off: iOS will only hand out kilometre-wide positions, and no route can be drawn from those."
            )
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

        // L'indicateur bleu, y compris avec « Toujours », où iOS ne l'impose
        // pas. Il dit à l'utilisateur que sa position est prise — c'est la
        // moindre des choses pour une app qui enregistre ses déplacements — et
        // il est du même coup le seul témoin lisible que le suivi tourne
        // vraiment : présent, l'app enregistre ; absent, elle ne reçoit rien,
        // et c'est là qu'il faut chercher.
        manager.showsBackgroundLocationIndicator = true

        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation

        // Aucun filtre de distance — c'était l'autre moitié de la trace en
        // pointillé.
        //
        // Il valait 10 m. Ça paraît fin : à 50 km/h, dix mètres passent en
        // sept dixièmes de seconde. Mais le filtre ne dit pas « livre-moi un
        // point tous les dix mètres », il dit « ne me réveille pas pour
        // moins » — et c'est sur cette permission qu'iOS s'appuie en
        // arrière-plan pour espacer les mesures elles-mêmes, l'app étant
        // réputée n'en avoir pas besoin plus souvent. Écran verrouillé, le
        // trajet revenait avec une dizaine de points pour vingt minutes.
        //
        // `kCLDistanceFilterNone` est le réglage des apps de navigation : une
        // mesure par seconde, ce qui fait la trace. Il faut le poser
        // explicitement, le gestionnaire étant partagé avec la surveillance des
        // changements significatifs et gardant ses réglages d'un usage à
        // l'autre.
        manager.distanceFilter = kCLDistanceFilterNone

        manager.pausesLocationUpdatesAutomatically = false

        // La session d'activité en arrière-plan (iOS 17), tenue tant que dure
        // le trajet. `allowsBackgroundLocationUpdates` demande à continuer en
        // arrière-plan ; la session, elle, maintient l'app « en cours
        // d'utilisation » aux yeux du système — c'est ce qui la met à l'abri
        // d'une suspension, où CoreLocation cesse de livrer et où le trajet ne
        // reprend qu'au réveil suivant, quelques centaines de mètres plus loin.
        // Elle est indispensable avec « Lorsque l'app est active », et sans
        // effet néfaste avec « Toujours ».
        backgroundSession = CLBackgroundActivitySession()

        trackingStartedAt = Date()
        lastDeliveryAt = nil
        manager.startUpdatingLocation()
        armWatchdog()
        AppLog.recording.notice("GPS tracking started (continuous, best-for-navigation).")
        return true
    }

    func stopActiveTracking() {
        watchdogTask?.cancel()
        watchdogTask = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
        trackingStartedAt = nil
        lastDeliveryAt = nil
        AppLog.recording.notice("GPS tracking stopped.")
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

    /// Relance le flux quand il s'est tu.
    ///
    /// Rien ne garantit qu'un `startUpdatingLocation` qui a réussi continue de
    /// livrer : iOS suspend l'app quand la mémoire manque, met le GPS en
    /// veille, et une session redémarrée en arrière-plan peut revenir muette.
    /// Rien, dans l'app, ne s'en apercevait — le trajet restait ouvert, le
    /// chronomètre tournait, et la trace s'arrêtait là où le flux s'était tu.
    ///
    /// Le chien de garde est ce qui manquait : il ne juge pas la qualité des
    /// points, seulement le silence, et un `stop` suivi d'un `start` suffit à
    /// réarmer une session endormie. Il ne tourne que pendant un trajet, et un
    /// redémarrage inutile ne coûte rien.
    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchdogPeriod)
                guard !Task.isCancelled, let self else { return }
                restartIfStalled()
            }
        }
    }

    private func restartIfStalled() {
        guard let startedAt = trackingStartedAt else { return }
        let silence = Date().timeIntervalSince(lastDeliveryAt ?? startedAt)
        guard silence >= Self.stallThreshold else { return }

        AppLog.recording.error("No location delivered for \(Int(silence))s — restarting GPS updates.")
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()
        // Repoussé plutôt que remis à zéro : sans ça, un flux réellement mort
        // ferait relancer à chaque tour de garde au lieu d'une fois par
        // fenêtre de silence.
        lastDeliveryAt = Date()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        onAuthorizationChange?(authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppLog.recording.error("Location manager failed: \(error.localizedDescription, privacy: .public)")
    }

    /// iOS met les livraisons en pause quand il juge que l'appareil ne bouge
    /// plus. `pausesLocationUpdatesAutomatically` est à `false`, donc ceci ne
    /// devrait jamais être appelé — mais si ça l'est, la pause est définitive :
    /// le système ne reprend de lui-même que dans certains cas, et un trajet
    /// s'arrêterait là sans un mot. Redémarrer coûte une ligne.
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard trackingStartedAt != nil else { return }
        AppLog.recording.error("iOS paused location updates mid-trip — restarting them.")
        manager.startUpdatingLocation()
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        AppLog.recording.notice("iOS resumed location updates.")
    }

    /// CoreLocation ne livre pas un point à la fois : `locations` est un paquet,
    /// rangé du plus ancien au plus récent. Au premier plan il n'en contient
    /// presque toujours qu'un, parce que l'app tourne en continu et que le
    /// système la réveille à chaque mesure. Écran verrouillé, il en contient
    /// des dizaines : iOS regroupe les livraisons pour économiser la batterie
    /// et vide le paquet quand il redonne du temps à l'app.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastDeliveryAt = Date()

        var accepted = 0
        for location in locations where isAcceptable(location) {
            accepted += 1
            onLocationUpdate?(location)
        }
        
        if trackingStartedAt == nil {
            onBackgroundWake?()
        }

        // Une ligne par livraison, pas par point : de quoi lire dans la Console
        // ce que l'arrière-plan reçoit vraiment. Un paquet de plusieurs points
        // dont le plus ancien a dix ou trente secondes, c'est le regroupement
        // à l'œuvre — le comportement normal, pas une anomalie.
        //
        // L'imprécision du dernier point y figure parce que c'est le chiffre
        // qui tranche quand la trace est trouée : des points reçus mais non
        // gardés, c'est le filtre ; aucun point reçu, c'est le flux.
        if let oldest = locations.first, let newest = locations.last {
            let age = Int(-oldest.timestamp.timeIntervalSinceNow)
            AppLog.recording.debug(
                "Location delivery: \(locations.count) point(s), \(accepted) kept, oldest \(age)s old, newest ±\(Int(newest.horizontalAccuracy))m."
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
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maxHorizontalAccuracy
        else { return false }
        // Pas de suivi actif : ce qui arrive ici vient de la surveillance des
        // changements significatifs, qui n'alimente pas de trajet.
        guard let startedAt = trackingStartedAt else { return false }
        guard location.timestamp >= startedAt.addingTimeInterval(-Self.startupTolerance) else { return false }
        return true
    }
}
