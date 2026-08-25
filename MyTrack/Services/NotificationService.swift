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
import SwiftData
import UserNotifications
import Observation

@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let modelContext: ModelContext

    private static let confirmCategoryIdentifier = "TRIP_CONFIRMATION"
    private static let confirmActionIdentifier = "TRIP_CONFIRM"
    private static let discardActionIdentifier = "TRIP_DISCARD"
    private static let tripIDKey = "tripID"
    private static let reportReadyIdentifier = "REPORT_READY"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        center.delegate = self
        registerCategory()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func scheduleTripConfirmationNotification(for trip: Trip) {
        let content = UNMutableNotificationContent()
        content.title = "Trajet terminé"
        content.body = "\(trip.formattedDistance) en \(trip.formattedDuration). Enregistrer ce trajet ?"
        content.sound = .default
        content.categoryIdentifier = Self.confirmCategoryIdentifier
        content.userInfo = [Self.tripIDKey: trip.id.uuidString]

        let request = UNNotificationRequest(identifier: trip.id.uuidString, content: content, trigger: nil)
        center.add(request)
    }

    /// Schedules the "your periodic report is ready" nudge for `dueDate`. The report
    /// itself isn't generated in the background — this just prompts the user to open
    /// the app, where the actual generation happens on next launch (see RootTabView).
    func scheduleReportReadyNotification(for dueDate: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reportReadyIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Votre rapport est prêt"
        content.body = "Ouvre MyTrack pour consulter ton rapport de trajets."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.reportReadyIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelReportReadyNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.reportReadyIdentifier])
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

        guard
            let idString = response.notification.request.content.userInfo[Self.tripIDKey] as? String,
            let trip = trip(withID: idString)
        else { return }

        switch response.actionIdentifier {
        case Self.confirmActionIdentifier:
            trip.confirmationStatus = .confirmed
            try? modelContext.save()
        case Self.discardActionIdentifier:
            modelContext.delete(trip)
            try? modelContext.save()
        default:
            break
        }
    }
}
