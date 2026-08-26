//
//  AppNotification.swift
//  MyTrack
//
//  An in-app notification, shown in the bell inbox on the recording screen.
//  Currently only created for periodic reports as they're generated (see
//  RootTabView), so `reportID` — the matching GeneratedReport.id — is always
//  set for now, but stays optional in case other kinds of notifications are
//  added later.
//

import Foundation
import SwiftData

@Model
final class AppNotification {
    var id: UUID
    var createdAt: Date
    var title: String
    var body: String
    var isRead: Bool
    var reportID: UUID?

    init(title: String, body: String, reportID: UUID? = nil) {
        self.id = UUID()
        self.createdAt = .now
        self.title = title
        self.body = body
        self.isRead = false
        self.reportID = reportID
    }
}
