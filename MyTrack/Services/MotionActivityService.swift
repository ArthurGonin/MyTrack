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
    /// traverse sans risque : quelques valeurs simples.
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
        ///
        /// `nil` tant qu'on roule, quand la fenêtre ne dit rien — et quand elle
        /// ne contient aucun échantillon automobile. Ce dernier cas rendait
        /// autrefois le premier échantillon de la fenêtre « faute de mieux » :
        /// voir plus bas pourquoi ce mieux-là était pire que rien.
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

        /// La date du dernier échantillon « en voiture » de la fenêtre,
        /// **toutes confiances confondues** — les `.low` compris.
        ///
        /// Les trois valeurs ci-dessus ne regardent que les échantillons sûrs,
        /// et ne lisent que le dernier d'entre eux. C'est ce qu'il faut pour
        /// *éteindre* le GPS, et il n'est pas question d'y toucher. Mais le
        /// même filtre servait aussi à l'*allumer*, et il y jetait justement le
        /// signal qui compte, pour deux raisons :
        ///
        /// - Core Motion annonce « en voiture » à confiance faible pendant la
        ///   première à la troisième minute d'un trajet. C'est le régime
        ///   ordinaire d'un départ, pas l'exception, et le chemin de rattrapage
        ///   n'en voyait donc pas un seul.
        /// - téléphone dans une poche, en ville, Core Motion intercale des
        ///   « je marche » et des « je ne bouge plus » entre les « en voiture ».
        ///   Le dernier échantillon sûr est alors un tirage au sort, et quand
        ///   il tombe mal, non seulement `isAutomotive` est faux mais
        ///   `isMovingUnderOwnPower` est vrai.
        ///
        /// `handle(_:)`, lui, ouvre un trajet sur un `.low` depuis toujours.
        /// Deux politiques opposées pour la même question — et c'est la stricte
        /// qui tournait en arrière-plan, c'est-à-dire au seul endroit où elle
        /// décide de quelque chose.
        ///
        /// `nil` quand la fenêtre ne contient aucun échantillon automobile.
        let lastAutomotiveAt: Date?

        /// Vrai quand ce dernier échantillon automobile était lui-même sûr.
        /// Distingue « il croit qu'on roule » de « il savait qu'on roulait ».
        let lastAutomotiveWasConfident: Bool

        /// La date du premier échantillon **sûr** de déplacement par ses propres
        /// moyens survenu *après* le dernier automobile.
        ///
        /// C'est la seule preuve qu'on ait d'être descendu du véhicule, et donc
        /// le seul motif de refuser d'ouvrir un trajet sur un soupçon. Un « je
        /// ne bouge plus » ne prouve rien : c'est un feu rouge autant qu'un
        /// stationnement — Core Motion marque d'ailleurs les deux à la fois,
        /// `stationary` et `automotive`, quand on attend au volant. `nil` tant
        /// que rien ne dit qu'on est sorti.
        let leftVehicleAt: Date?

        static let nothingKnown = DrivingReading(
            isAutomotive: false,
            stoppedAt: nil,
            isMovingUnderOwnPower: false,
            lastAutomotiveAt: nil,
            lastAutomotiveWasConfident: false,
            leftVehicleAt: nil
        )
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
        guard isAvailable, isAuthorized else { return .nothingKnown }
        let end = Date()
        let start = end.addingTimeInterval(-interval)
        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
                if let error {
                    AppLog.recording.error(
                        "Recent activity query failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let all = activities ?? []

                // Première lecture : le soupçon, sur *tous* les échantillons,
                // `.low` compris — voir `DrivingReading.lastAutomotiveAt`. La
                // requête les rend du plus ancien au plus récent, donc le
                // dernier automobile rencontré est bien le dernier dans le
                // temps.
                var lastAutomotiveAt: Date?
                var lastAutomotiveWasConfident = false
                var leftVehicleAt: Date?
                for activity in all {
                    if activity.automotive {
                        lastAutomotiveAt = activity.startDate
                        lastAutomotiveWasConfident = activity.confidence != .low
                        // Ce qui suit un « en voiture » recommence à compter :
                        // la marche *jusqu'à* la voiture ne dit rien de la fin
                        // du trajet, et sans cette remise à zéro elle
                        // interdirait d'ouvrir celui qu'elle précède.
                        leftVehicleAt = nil
                        continue
                    }
                    guard leftVehicleAt == nil,
                          activity.confidence != .low,
                          Self.isMovingUnderOwnPower(activity)
                    else { continue }
                    leftVehicleAt = activity.startDate
                }

                // Seconde lecture : la certitude. Inchangée — c'est elle qui
                // ferme un trajet, et elle continue d'exiger un signal sûr.
                let usable = all.filter { $0.confidence != .low }
                guard let latest = usable.last else {
                    continuation.resume(returning: DrivingReading(
                        isAutomotive: false,
                        stoppedAt: nil,
                        isMovingUnderOwnPower: false,
                        lastAutomotiveAt: lastAutomotiveAt,
                        lastAutomotiveWasConfident: lastAutomotiveWasConfident,
                        leftVehicleAt: leftVehicleAt
                    ))
                    return
                }
                guard !latest.automotive else {
                    continuation.resume(returning: DrivingReading(
                        isAutomotive: true,
                        stoppedAt: nil,
                        isMovingUnderOwnPower: false,
                        lastAutomotiveAt: lastAutomotiveAt,
                        lastAutomotiveWasConfident: lastAutomotiveWasConfident,
                        leftVehicleAt: leftVehicleAt
                    ))
                    return
                }
                // Le premier échantillon non-automobile qui suit le dernier
                // automobile : c'est là que la conduite s'est arrêtée.
                //
                // Rien du tout quand la fenêtre ne contient aucun automobile, et
                // c'est un changement. On rendait alors son premier échantillon,
                // en supposant une fenêtre qui aurait commencé après l'arrêt. Or
                // le seul lecteur de cette date — `DrivingDetector.recheckDriving`
                // — interroge une fenêtre ancrée au *début du trajet en cours*,
                // c'est-à-dire le cas exactement inverse, et le repli y datait la
                // fin d'une conduite du moment où l'on marchait encore vers la
                // voiture : Core Motion n'annonce « en voiture » qu'en confiance
                // faible pendant les premières minutes (voir `lastAutomotiveAt`),
                // `usable` n'en contenait donc aucun, et le trajet naissant se
                // faisait clore sur la marche qui l'avait précédé — trace
                // tronquée à son propre début, trajet supprimé ou enregistré à
                // zéro mètre.
                //
                // Ne rien rendre est la seule réponse juste : d'ici on ignore sur
                // quelle période l'appelant interroge, donc ce que son silence
                // veut dire. Deviner à la place de Core Motion est précisément ce
                // que son lecteur se refuse à faire.
                let stoppedAt = usable.lastIndex(where: { $0.automotive })
                    .map { usable[usable.index(after: $0)].startDate }
                continuation.resume(returning: DrivingReading(
                    isAutomotive: false,
                    stoppedAt: stoppedAt,
                    isMovingUnderOwnPower: Self.isMovingUnderOwnPower(latest),
                    lastAutomotiveAt: lastAutomotiveAt,
                    lastAutomotiveWasConfident: lastAutomotiveWasConfident,
                    leftVehicleAt: leftVehicleAt
                ))
            }
        }
    }

    /// Vrai quand l'échantillon dit que la personne se déplace par ses propres
    /// moyens. `nonisolated` parce que le bloc de rappel de Core Motion, d'où
    /// elle est appelée, ne l'est pas non plus.
    nonisolated private static func isMovingUnderOwnPower(_ activity: CMMotionActivity) -> Bool {
        activity.walking || activity.running || activity.cycling
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
