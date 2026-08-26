//
//  NotificationInboxView.swift
//  MyTrack
//
//  Sheet opened from the bell on the recording screen: history of received
//  notifications (currently just "your periodic report is ready" nudges).
//  Opening this view marks every notification read, which is what clears the
//  bell's red dot. Tapping a report notification doesn't open the PDF
//  directly — it deep-links into Account Settings > Rapport > Historique des
//  rapports, and opens the new report from there.
//

import SwiftUI
import SwiftData

struct NotificationInboxView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppNotification.createdAt, order: .reverse) private var notifications: [AppNotification]

    var body: some View {
        NavigationStack {
            Group {
                if notifications.isEmpty {
                    ContentUnavailableView(
                        "Aucune notification",
                        systemImage: "bell",
                        description: Text("Les notifications reçues apparaîtront ici.")
                    )
                } else {
                    List {
                        ForEach(notifications) { notification in
                            notificationRow(notification)
                        }
                        .onDelete(perform: deleteNotifications)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear {
            appServices.notificationInboxService.markAllRead(notifications, in: modelContext)
        }
    }

    private func notificationRow(_ notification: AppNotification) -> some View {
        Button {
            open(notification)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(notification.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(notification.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ notification: AppNotification) {
        guard let reportID = notification.reportID else { return }
        appServices.pendingReportToOpen = reportID
        dismiss()
    }

    private func deleteNotifications(at offsets: IndexSet) {
        for index in offsets {
            appServices.notificationInboxService.deleteNotification(notifications[index], in: modelContext)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self, AppNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(AppNotification(title: "Votre rapport est prêt", body: "Le rapport « Mensuel » est prêt."))
    return NotificationInboxView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
