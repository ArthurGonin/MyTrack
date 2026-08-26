//
//  NotificationInboxService.swift
//  MyTrack
//
//  Persists the in-app notification history shown from the bell on the
//  recording screen — distinct from NotificationService, which schedules the
//  system (UNUserNotificationCenter) notifications.
//

import Foundation
import SwiftData

final class NotificationInboxService {
    func addReportReadyNotification(for report: GeneratedReport, in context: ModelContext) {
        let notification = AppNotification(
            title: "Votre rapport est prêt",
            body: "Le rapport « \(report.profileName ?? "Rapport périodique") » est prêt.",
            reportID: report.id
        )
        context.insert(notification)
        context.saveOrLog()
    }

    func deleteNotification(_ notification: AppNotification, in context: ModelContext) {
        context.delete(notification)
        context.saveOrLog()
    }

    func markAllRead(_ notifications: [AppNotification], in context: ModelContext) {
        var didChange = false
        for notification in notifications where !notification.isRead {
            notification.isRead = true
            didChange = true
        }
        if didChange {
            context.saveOrLog()
        }
    }
}
