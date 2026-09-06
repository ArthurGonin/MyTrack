//
//  NotificationService.swift
//  MyTrack
//
//  Wraps UNUserNotificationCenter: sends the actionable "did you make this
//  trip?" notification for a just-finalized automatic trip, and resolves the
//  user's response (confirm / discard) directly against SwiftData. Owns its
//  own UNUserNotificationCenterDelegate conformance so everything about
//  notification handling lives in one file, instead of splitting scheduling
//  from response-handling across NotificationService and AppDelegate.
//

import Foundation
import OSLog
import SwiftData
import UserNotifications
import Observation

@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let modelContext: ModelContext
    private let unitSettingsService: UnitSettingsService
    private let languageService: LanguageService

    private static let confirmCategoryIdentifier = "TRIP_CONFIRMATION"
    private static let confirmActionIdentifier = "TRIP_CONFIRM"
    private static let discardActionIdentifier = "TRIP_DISCARD"
    private static let tripIDKey = "tripID"
    private static let reportReadyKey = "reportReady"
    private static let reportReadyIdentifierPrefix = "REPORT_READY_"

    /// Combien d'échéances à venir sont armées d'un coup. Voir
    /// `scheduleReportReadyNotifications`.
    private static let scheduledReportOccurrences = 3
    private static let subscriptionLapsedIdentifier = "SUBSCRIPTION_LAPSED"

    /// Raised when the user taps a "your report is ready" notification, so the
    /// app can bring them to the Rapports tab. Consumed — and reset — by
    /// RootTabView. The report itself isn't named here: at the time the
    /// notification was scheduled it didn't exist yet, and it only gets
    /// generated once the app is opened.
    var shouldOpenReportsTab = false

    /// Raised when the user taps a trip-confirmation notification itself rather
    /// than one of its Yes/No actions. Consumed — and reset — by RootTabView.
    /// Without it that tap did nothing at all on a running app: the review
    /// screen is otherwise only ever presented at launch, so a detected trip
    /// could sit unconfirmed with nothing left pointing at it.
    var shouldOpenPendingTripsReview = false

    init(
        modelContext: ModelContext,
        unitSettingsService: UnitSettingsService,
        languageService: LanguageService
    ) {
        self.modelContext = modelContext
        self.unitSettingsService = unitSettingsService
        self.languageService = languageService
        super.init()
        center.delegate = self
        registerCategory()
    }

    /// La langue de l'app, relue à chaque envoi : une notification écrite au
    /// lancement dans une langue et affichée après un changement de langue
    /// serait la seule partie de l'app restée en arrière.
    private var locale: Locale { languageService.locale }

    /// Voir `LanguageService.bundle` : c'est lui, et pas la locale, qui décide
    /// dans quelle langue une chaîne construite hors SwiftUI est écrite.
    private var bundle: Bundle { languageService.bundle }

    /// L'état courant, relu à la demande.
    ///
    /// Contrairement à la position, iOS ne prévient personne quand
    /// l'autorisation de notification change : il n'y a pas de délégué à
    /// écouter, seulement cette lecture. Les réglages la refont donc à
    /// l'affichage et au retour au premier plan.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Demande l'autorisation et attend la réponse.
    ///
    /// Attendre, plutôt que de lancer la demande et repartir : la ligne des
    /// réglages qui l'appelle doit se remettre à jour sur ce que l'utilisateur
    /// vient de répondre, et elle n'a aucun autre moyen de l'apprendre.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted {
                AppLog.recording.notice("Notifications denied — trips will only be confirmable from the in-app review screen.")
            }
            return granted
        } catch {
            AppLog.recording.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func scheduleTripConfirmationNotification(for trip: Trip) {
        // Les titres des boutons Oui/Non sont figés dans la catégorie au moment
        // où on l'enregistre : la ré-enregistrer ici est ce qui les garde dans
        // la langue courante après un changement de langue.
        registerCategory()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Un trajet a été détecté", bundle: bundle, locale: locale)
        let distance = trip.formattedDistance(in: unitSettingsService.distanceUnit, locale: locale)
        let duration = trip.formattedDuration(locale: locale)
        // La distance et la durée restent dans le corps : ce sont elles qui
        // permettent de répondre depuis l'écran verrouillé, sans ouvrir l'app
        // pour savoir de quel trajet il s'agit.
        content.body = String(localized: "\(distance) en \(duration). Voulez-vous l'enregistrer ?", bundle: bundle, locale: locale)
        content.sound = .default
        content.categoryIdentifier = Self.confirmCategoryIdentifier
        content.userInfo = [Self.tripIDKey: trip.id.uuidString]

        let request = UNNotificationRequest(identifier: trip.id.uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                AppLog.recording.error("Trip confirmation notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Schedules the "your periodic report is ready" nudge for `dueDate`. The report
    /// itself isn't generated in the background — this just prompts the user to open
    /// the app, where the actual generation happens on next launch (see RootTabView).
    /// Identified per-profile so several periodic report profiles can each have their
    /// own pending notification without cancelling one another.
    func scheduleReportReadyNotifications(for profile: ReportProfile) {
        cancelReportReadyNotification(profileID: profile.id)
        guard var dueDate = profile.nextDueDate else { return }

        // Les échéances à venir sont armées d'avance, et non une par une.
        //
        // La suivante n'était programmée qu'*après* une génération, laquelle
        // n'a lieu qu'à l'ouverture de l'app : ignorer le rappel d'octobre et
        // ne pas ouvrir MyTrack du mois suffisait donc à ce que celui de
        // novembre n'arrive jamais. Rien ne le disait, et les rapports, eux,
        // étaient bien rattrapés à la réouverture — l'utilisateur perdait
        // l'alerte, pas le document.
        //
        // Trois suffisent à franchir deux périodes muettes, et restent loin des
        // soixante-quatre notifications qu'iOS garde en attente par app, même
        // avec plusieurs profils.
        for occurrence in 0..<Self.scheduledReportOccurrences {
            schedule(at: dueDate, profileID: profile.id, profileName: profile.name, occurrence: occurrence)
            guard let next = ReportPeriodBoundary.nextDueDate(
                after: dueDate,
                periodicity: profile.periodicity,
                customIntervalDays: profile.customIntervalDays
            ) else { return }
            dueDate = next
        }
    }

    private func schedule(at dueDate: Date, profileID: UUID, profileName: String, occurrence: Int) {
        let identifier = reportReadyIdentifier(for: profileID, occurrence: occurrence)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Votre rapport est prêt", bundle: bundle, locale: locale)
        content.body = String(localized: "Le rapport « \(profileName) » est prêt dans MyTrack.", bundle: bundle, locale: locale)
        content.sound = .default
        content.userInfo = [Self.reportReadyKey: true]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                AppLog.reports.error("Report-ready notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Envoyée au moment précis où l'enregistrement s'arrête. C'est la seule
    /// alerte qui atteint l'utilisateur app fermée — donc la seule qui puisse
    /// lui épargner de découvrir trois semaines plus tard que rien n'a été
    /// enregistré.
    ///
    /// Le texte nomme les deux choses que l'abonnement paie, l'enregistrement
    /// et la création de rapports, depuis que la seconde est passée derrière
    /// lui : ne parler que des trajets laissait croire que le reste marchait
    /// encore. Il reste court malgré tout — une notification se lit en deux
    /// lignes, et la troisième phrase est ce que l'utilisateur veut savoir
    /// tout de suite : ce qu'il a déjà ne disparaît pas.
    func notifySubscriptionLapsed(hasBillingIssue: Bool) {
        let content = UNMutableNotificationContent()
        if hasBillingIssue {
            content.title = String(localized: "Problème de paiement", bundle: bundle, locale: locale)
            content.body = String(
                localized: "Votre abonnement n'a pas pu être renouvelé : vos trajets ne sont plus enregistrés et vous ne pouvez plus créer de rapport. Mettez à jour votre moyen de paiement.",
                bundle: bundle,
                locale: locale
            )
        } else {
            content.title = String(localized: "Abonnement expiré", bundle: bundle, locale: locale)
            content.body = String(
                localized: "Vos trajets ne sont plus enregistrés et vous ne pouvez plus créer de rapport. Ce qui est déjà enregistré reste accessible.",
                bundle: bundle,
                locale: locale
            )
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.subscriptionLapsedIdentifier,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                AppLog.purchases.error("Subscription lapse notification failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Retire la demande de confirmation d'un trajet, livrée comme en attente.
    ///
    /// À appeler dès qu'un trajet quitte `.pendingConfirmation` par un autre
    /// chemin — l'écran de revue, typiquement. Sans ça la notification reste au
    /// centre de notifications avec ses deux boutons, et « Oui » appuyé le
    /// lendemain ramènerait un trajet que son propriétaire a supprimé.
    ///
    /// `removeDelivered` *et* `removePending` : la première a été livrée sans
    /// déclencheur, mais rien ne garantit qu'elle l'ait été — l'app pouvait
    /// être en train de s'éteindre.
    func cancelTripConfirmationNotification(tripID: UUID) {
        let identifier = tripID.uuidString
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelReportReadyNotification(profileID: UUID) {
        // L'identifiant sans rang est celui d'avant les échéances multiples. Un
        // appareil mis à jour en garde un par profil, qu'aucun des nouveaux ne
        // recouvre : sans cette ligne il resterait armé pour toujours, et
        // doublerait le premier rappel au lieu de le remplacer.
        var identifiers = [Self.reportReadyIdentifierPrefix + profileID.uuidString]
        identifiers += (0..<Self.scheduledReportOccurrences).map {
            reportReadyIdentifier(for: profileID, occurrence: $0)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Annule les nudges de rapport encore en attente, sans avoir à connaître
    /// les profils : appelée quand l'abonnement tombe, alors qu'aucun de ces
    /// rapports ne sera plus généré.
    func cancelReportReadyNotifications() {
        // Le centre et le préfixe sont relevés ici, sur le fil principal : la
        // closure ci-dessous, elle, est rappelée par UserNotifications sur la
        // sienne, et n'a pas le droit d'aller lire des propriétés d'un objet qui
        // vit sur le fil principal.
        let center = center
        let prefix = Self.reportReadyIdentifierPrefix
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    /// Le rang est dans l'identifiant, faute de quoi les trois échéances
    /// armées ensemble s'écraseraient l'une l'autre — et le préfixe reste en
    /// tête, pour que `cancelReportReadyNotifications` continue de toutes les
    /// reconnaître sans connaître les profils.
    private func reportReadyIdentifier(for profileID: UUID, occurrence: Int) -> String {
        "\(Self.reportReadyIdentifierPrefix)\(profileID.uuidString)_\(occurrence)"
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func registerCategory() {
        let confirmAction = UNNotificationAction(
            identifier: Self.confirmActionIdentifier,
            title: String(localized: "Oui, enregistrer", bundle: bundle, locale: locale),
            options: []
        )
        let discardAction = UNNotificationAction(
            identifier: Self.discardActionIdentifier,
            title: String(localized: "Non", bundle: bundle, locale: locale),
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.confirmCategoryIdentifier,
            actions: [confirmAction, discardAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func trip(withID idString: String) -> Trip? {
        guard let id = UUID(uuidString: idString) else { return nil }
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Sans ça, une notif programmée pendant que l'app est au premier plan
        // ne s'affiche pas du tout — utile pour tester l'étape 5 sans mettre
        // l'app en arrière-plan.
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo

        if userInfo[Self.reportReadyKey] != nil {
            shouldOpenReportsTab = true
            return
        }

        guard let idString = userInfo[Self.tripIDKey] as? String else { return }

        // Handled before the trip is looked up: opening the review screen is
        // still the right answer when this particular trip has since been
        // resolved elsewhere, since others may well be waiting.
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            shouldOpenPendingTripsReview = true
            return
        }

        guard let trip = trip(withID: idString) else { return }

        // Une notification survit à ce qu'elle annonçait : celle-ci reste
        // affichée alors que le trajet a pu être répondu dans l'app, supprimé,
        // ou fusionné avec d'autres depuis. Répondre « Oui » ramènerait alors un
        // trajet mis à la corbeille — et, sur un composant de fusion, le
        // remettrait dans la liste *en plus* du trajet qui le contient déjà,
        // doublant sa distance dans les totaux et dans les rapports.
        //
        // Seul un trajet encore en attente se laisse donc répondre ; pour les
        // autres, il n'y a rien à faire que retirer une notification périmée.
        guard trip.confirmationStatus == .pendingConfirmation else {
            cancelTripConfirmationNotification(tripID: trip.id)
            return
        }

        switch response.actionIdentifier {
        case Self.confirmActionIdentifier:
            trip.confirmationStatus = .confirmed
            modelContext.saveOrLog()
        case Self.discardActionIdentifier:
            trip.confirmationStatus = .deleted
            modelContext.saveOrLog()
        default:
            break
        }
    }
}
