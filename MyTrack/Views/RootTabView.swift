//
//  RootTabView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices
    @State private var isPendingReviewPresented = false

    var body: some View {
        TabView {
            RecordTripView()
                .tabItem {
                    Label("Enregistrer", systemImage: "record.circle")
                }
            TripListView()
                .tabItem {
                    Label("Trajets", systemImage: "list.bullet")
                }
        }
        .onAppear {
            let descriptor = FetchDescriptor<Trip>()
            let hasPendingTrips = ((try? modelContext.fetch(descriptor)) ?? [])
                .contains { $0.confirmationStatus == .pendingConfirmation }
            if hasPendingTrips {
                isPendingReviewPresented = true
            }
            generatePeriodicReportIfDue()
        }
        .sheet(isPresented: $isPendingReviewPresented) {
            PendingTripsReviewView()
        }
    }

    /// If a periodic report is due (per ReportSettings.nextDueDate), generates it from
    /// the confirmed trips in that period and reschedules the "report ready" notification.
    /// On failure, nextDueDate is left untouched so the check simply retries next launch.
    private func generatePeriodicReportIfDue() {
        let settings = appServices.reportSettingsService.currentSettings(in: modelContext)
        guard let period = appServices.reportSettingsService.periodDueForGeneration(settings: settings, now: .now) else {
            return
        }

        let periodStart = period.periodStart
        let periodEnd = period.periodEnd
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.startDate >= periodStart && $0.startDate < periodEnd }
        )
        let tripsInPeriod = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.confirmationStatus == .confirmed }

        do {
            try appServices.reportGenerationService.generateReport(
                trips: tripsInPeriod,
                periodStart: periodStart,
                periodEnd: periodEnd,
                source: .periodic,
                in: modelContext
            )
            if let newDueDate = appServices.reportSettingsService.advanceAfterGeneration(
                settings: settings, generatedThrough: periodEnd, in: modelContext
            ) {
                appServices.notificationService.scheduleReportReadyNotification(for: newDueDate)
            }
        } catch {
            // Left nextDueDate untouched on purpose — retried on next launch.
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportSettings.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
