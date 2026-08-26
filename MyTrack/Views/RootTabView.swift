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
            generatePeriodicReportsIfDue()
        }
        .sheet(isPresented: $isPendingReviewPresented) {
            PendingTripsReviewView()
        }
    }

    /// Checks every periodic report profile independently: for each one that's due (per
    /// its own `nextDueDate`), generates it from the confirmed trips in that period —
    /// filtered to the profile's vehicles, if any are set — and reschedules that
    /// profile's own "report ready" notification. On failure, a profile's `nextDueDate`
    /// is left untouched so it simply retries next launch, without affecting the others.
    private func generatePeriodicReportsIfDue() {
        let profiles = appServices.reportProfileService.allProfiles(in: modelContext)
        for profile in profiles {
            guard let period = appServices.reportProfileService.periodDueForGeneration(profile: profile, now: .now) else {
                continue
            }

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

            do {
                try appServices.reportGenerationService.generateReport(
                    trips: tripsInPeriod,
                    periodStart: periodStart,
                    periodEnd: periodEnd,
                    source: .periodic,
                    profileName: profile.name,
                    includedVehicles: profile.vehicles,
                    in: modelContext
                )
                if let newDueDate = appServices.reportProfileService.advanceAfterGeneration(
                    profile: profile, generatedThrough: periodEnd, in: modelContext
                ) {
                    appServices.notificationService.scheduleReportReadyNotification(
                        for: newDueDate, profileID: profile.id, profileName: profile.name
                    )
                }
            } catch {
                // Left nextDueDate untouched on purpose — retried on next launch.
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
