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

    private static let confirmCategoryIdentifier = "TRIP_CONFIRMATION"
    private static let confirmActionIdentifier = "TRIP_CONFIRM"
    private static let discardActionIdentifier = "TRIP_DISCARD"
    private static let tripIDKey = "tripID"
    private static let reportReadyKey = "reportReady"
    private static let reportReadyIdentifierPrefix = "REPORT_READY_"

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

    init(modelContext: ModelContext, unitSettingsService: UnitSettingsService) {
        self.modelContext = modelContext
        self.unitSettingsService = unitSettingsService
        super.init()
        center.delegate = self
        registerCategory()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLog.recording.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                AppLog.recording.notice("Notifications denied — trips will only be confirmable from the in-app review screen.")
            }
        }
    }

    func scheduleTripConfirmationNotification(for trip: Trip) {
        let content = UNMutableNotificationContent()
        content.title = "Trajet terminé"
        let distance = trip.formattedDistance(in: unitSettingsService.distanceUnit)
        content.body = "\(distance) en \(trip.formattedDuration). Enregistrer ce trajet ?"
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
    func scheduleReportReadyNotification(for dueDate: Date, profileID: UUID, profileName: String) {
        let identifier = reportReadyIdentifier(for: profileID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Votre rapport est prêt"
        content.body = "Le rapport « \(profileName) » est prêt dans MyTrack."
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

    func cancelReportReadyNotification(profileID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [reportReadyIdentifier(for: profileID)])
    }

    private func reportReadyIdentifier(for profileID: UUID) -> String {
        Self.reportReadyIdentifierPrefix + profileID.uuidString
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func registerCategory() {
        let confirmAction = UNNotificationAction(
            identifier: Self.confirmActionIdentifier,
            title: "Oui, enregistrer",
            options: []
        )
        let discardAction = UNNotificationAction(
            identifier: Self.discardActionIdentifier,
            title: "Non",
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
