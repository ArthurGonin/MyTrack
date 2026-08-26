//
//  RootTabView.swift
//  MyTrack
//

import SwiftUI
import OSLog
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices
    @State private var isPendingReviewPresented = false
    @State private var isNotificationReportPresented = false

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
            // Deliberately a plain Task rather than .task: report generation
            // must not be cancelled by leaving the tab, or a PDF could be
            // written with no matching record ever created for it.
            Task { await generatePeriodicReportsIfDue() }
        }
        .sheet(isPresented: $isPendingReviewPresented) {
            PendingTripsReviewView()
        }
        // Handled once here, at the tab root, rather than in the per-tab
        // account toolbar: TabView keeps both tabs alive, so a per-tab
        // listener on `pendingReportToOpen` would fire twice and could try to
        // present two settings sheets at once.
        .onChange(of: appServices.pendingReportToOpen) { _, newValue in
            isNotificationReportPresented = newValue != nil
        }
        .sheet(isPresented: $isNotificationReportPresented) {
            AccountSettingsView(openingReportID: appServices.pendingReportToOpen)
                .onDisappear { appServices.pendingReportToOpen = nil }
        }
    }

    /// Bounded so that a due date corrupted into the distant past can't spin
    /// generating reports forever.
    private static let maxCatchUpReportsPerProfile = 24

    /// Checks every periodic report profile independently, generating one report per
    /// period that came due — not just one per launch, so reopening the app after a
    /// long gap doesn't take several launches to produce the reports that were missed
    /// meanwhile. A profile that fails is left alone and simply retried next launch,
    /// without affecting the others.
    private func generatePeriodicReportsIfDue() async {
        for profile in appServices.reportProfileService.allProfiles(in: modelContext) {
            var generatedCount = 0
            while generatedCount < Self.maxCatchUpReportsPerProfile,
                  let period = appServices.reportProfileService.periodDueForGeneration(profile: profile, now: .now) {
                guard await generateReport(for: profile, over: period) else { break }
                generatedCount += 1
            }
        }
    }

    /// Returns false when generation failed, leaving `nextDueDate` untouched on
    /// purpose so the period is retried rather than skipped.
    private func generateReport(
        for profile: ReportProfile,
        over period: (periodStart: Date, periodEnd: Date)
    ) async -> Bool {
        let periodStart = period.periodStart
        let periodEnd = period.periodEnd
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.startDate >= periodStart && $0.startDate < periodEnd }
        )
        var tripsInPeriod = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.confirmationStatus == .confirmed }
        if !profile.vehicles.isEmpty {
            let vehicleIDs = Set(profile.vehicles.map(\.persistentModelID))
            tripsInPeriod = tripsInPeriod.filter { trip in
                guard let vehicle = trip.vehicle else { return false }
                return vehicleIDs.contains(vehicle.persistentModelID)
            }
        }

        let report: GeneratedReport
        do {
            report = try await appServices.reportGenerationService.generateReport(
                trips: tripsInPeriod,
                periodStart: periodStart,
                periodEnd: periodEnd,
                source: .periodic,
                profileName: profile.name,
                includedVehicles: profile.vehicles,
                in: modelContext
            )
        } catch {
            AppLog.reports.error(
                "Periodic report failed for \(profile.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        appServices.notificationInboxService.addReportReadyNotification(for: report, in: modelContext)

        if let newDueDate = appServices.reportProfileService.advanceAfterGeneration(
            profile: profile, generatedThrough: periodEnd, in: modelContext
        ) {
            appServices.notificationService.scheduleReportReadyNotification(
                for: newDueDate, profileID: profile.id, profileName: profile.name
            )
        }
        return true
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self, AppNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
