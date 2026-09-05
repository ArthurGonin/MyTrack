//
//  MotionActivityService.swift
//  MyTrack
//

import Foundation
import OSLog
import CoreMotion

final class MotionActivityService {
    private let activityManager = CMMotionActivityManager()

    /// False on devices without a motion coprocessor — and in the Simulator,
    /// where automatic detection can't be exercised at all.
    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    /// Whether the user has already granted Motion & Fitness access.
    ///
    /// Worth checking before arming monitoring, because startActivityUpdates
    /// raises the system prompt as a side effect: without this, the app asks
    /// for motion access at whatever moment monitoring happens to start —
    /// a cold launch, for instance — instead of at the point in onboarding
    /// where the user asked for automatic tracking.
    var isAuthorized: Bool { CMMotionActivityManager.authorizationStatus() == .authorized }

    /// L'état complet, et pas seulement « autorisé ou non ».
    ///
    /// Les réglages ont besoin de distinguer un refus d'une question jamais
    /// posée : au refus, iOS ne réaffichera plus jamais sa fenêtre et seul son
    /// app Réglages peut encore lever l'interdiction ; à la question jamais
    /// posée, la demande fait bien apparaître la fenêtre système.
    var authorizationStatus: CMAuthorizationStatus { CMMotionActivityManager.authorizationStatus() }

    /// Triggers the Motion & Fitness system prompt (if not already determined)
    /// and waits for the user's answer. CoreMotion has no dedicated "request
    /// authorization" API with a completion, so this queries a negligible
    /// time window instead — queryActivityStarting's handler reliably fires
    /// once authorization is resolved, granted or denied, unlike
    /// startActivityUpdates, which simply stays silent on denial.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let now = Date()
        await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: now, to: now, to: .main) { _, _ in
                continuation.resume()
            }
        }
    }

    /// Ce que Core Motion sait de la conduite récente, réduit à ce qui se
    /// traverse sans risque : deux valeurs simples.
    ///
    /// La requête rend des `CMMotionActivity`, qui sont des objets et non des
    /// valeurs — les faire sortir du bloc de rappel les ferait franchir une
    /// frontière d'isolation que la concurrence stricte refuse. Tout est donc
    /// lu à l'intérieur, et c'est ce résumé-là qui sort.
    nonisolated struct DrivingReading: Sendable {
        /// Vrai quand le dernier échantillon utilisable dit « en voiture ».
        let isAutomotive: Bool

        /// Le moment où la conduite a cessé, quand elle a cessé : l'heure du
        /// premier échantillon non-automobile qui suit le dernier automobile.
        /// `nil` tant qu'on roule, ou quand la fenêtre ne dit rien.
        let stoppedAt: Date?

        /// Vrai quand le dernier échantillon utilisable dit que la personne se
        /// déplace par ses propres moyens — elle marche, court ou pédale.
        ///
        /// C'est la différence entre « la voiture ne bouge plus » et « la
        /// personne est sortie de la voiture », que `stoppedAt` seul ne dit
        /// pas. Un feu rouge et un stationnement produisent le même
        /// « immobile » ; seul un « je marche » tranche. Ce que
        /// `DrivingDetector` en fait est sa politique à lui, pas celle d'ici.
        let isMovingUnderOwnPower: Bool
    }

    /// Ce que dit l'historique de mouvement des `interval` dernières secondes.
    ///
    /// Nécessaire parce que `startActivityUpdates` ne livre que des
    /// *changements*, à partir du moment où on l'arme. Deux situations en
    /// découlent, et cette requête est la réponse aux deux :
    ///
    /// - un trajet déjà en cours quand la surveillance démarre — l'app
    ///   réveillée d'une terminaison par un changement de position significatif,
    ///   le cas même pour lequel toute cette fonctionnalité existe — ne produit
    ///   aucun échantillon avant sa fin, et serait manqué ;
    /// - un trajet en cours pendant lequel l'app est suspendue ne voit pas
    ///   passer les échantillons vivants, et se retrouve à décider sur une
    ///   lecture périmée.
    ///
    /// Seul le dernier échantillon utilisable compte pour `isAutomotive`, et
    /// non n'importe quel échantillon automobile de la fenêtre : une conduite
    /// terminée il y a deux minutes ne doit pas ressusciter en trajet auquel il
    /// ne resterait plus aucun changement pour le clore.
    func recentDriving(lookingBack interval: TimeInterval) async -> DrivingReading {
        let nothingKnown = DrivingReading(isAutomotive: false, stoppedAt: nil, isMovingUnderOwnPower: false)
        guard isAvailable, isAuthorized else { return nothingKnown }
        let end = Date()
        let start = end.addingTimeInterval(-interval)
        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
                if let error {
                    AppLog.recording.error(
                        "Recent activity query failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let usable = (activities ?? []).filter { $0.confidence != .low }
                guard let latest = usable.last else {
                    continuation.resume(returning: nothingKnown)
                    return
                }
                guard !latest.automotive else {
                    continuation.resume(returning: DrivingReading(
                        isAutomotive: true, stoppedAt: nil, isMovingUnderOwnPower: false
                    ))
                    return
                }
                // Le premier échantillon non-automobile qui suit le dernier
                // automobile : c'est là que la conduite s'est arrêtée. Si la
                // fenêtre ne contient rien d'automobile, elle a commencé après
                // l'arrêt, et son premier échantillon est le mieux qu'on ait.
                let stoppedAt: Date
                if let lastAutomotive = usable.lastIndex(where: { $0.automotive }) {
                    stoppedAt = usable[usable.index(after: lastAutomotive)].startDate
                } else {
                    stoppedAt = usable[0].startDate
                }
                continuation.resume(returning: DrivingReading(
                    isAutomotive: false,
                    stoppedAt: stoppedAt,
                    isMovingUnderOwnPower: latest.walking || latest.running || latest.cycling
                ))
            }
        }
    }

    /// Whether the device reads as driving *right now*. See `recentDriving`.
    func isAutomotiveNow(lookingBack interval: TimeInterval) async -> Bool {
        await recentDriving(lookingBack: interval).isAutomotive
    }

    func startMonitoring(onUpdate: @escaping (CMMotionActivity) -> Void) {
        guard isAvailable else {
            AppLog.recording.notice("Motion activity updates are unavailable on this device.")
            return
        }
        activityManager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            onUpdate(activity)
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
    }
}
