//
//  NotificationBellButton.swift
//  MyTrack
//
//  Toolbar bell on the recording screen: opens the notification inbox, with
//  a red dot shown whenever it holds an unread notification.
//

import SwiftUI
import SwiftData

struct NotificationBellButton: View {
    @Query(sort: \AppNotification.createdAt, order: .reverse) private var notifications: [AppNotification]
    @State private var isPresented = false

    private var hasUnread: Bool {
        notifications.contains { !$0.isRead }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if hasUnread {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(hasUnread ? "Notifications, nouveau rapport disponible" : "Notifications")
        .sheet(isPresented: $isPresented) {
            NotificationInboxView()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: AppNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(AppNotification(title: "Votre rapport est prêt", body: "Le rapport « Mensuel » est prêt."))
    return NotificationBellButton()
        .padding()
        .modelContainer(container)
}
