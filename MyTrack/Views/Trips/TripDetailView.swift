//
//  TripDetailView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingVehiclePicker = false

    var body: some View {
        List {
            Section("Trajet") {
                LabeledContent("Début", value: trip.startDate.formatted(date: .abbreviated, time: .shortened))
                if let endDate = trip.endDate {
                    LabeledContent("Fin", value: endDate.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Durée", value: trip.formattedDuration)
                LabeledContent("Distance", value: trip.formattedDistance)
            }
            Section("Détails") {
                Button {
                    isPresentingVehiclePicker = true
                } label: {
                    LabeledContent("Véhicule", value: trip.vehicle?.name ?? "Aucun véhicule")
                }
                .buttonStyle(.plain)
                LabeledContent("Source", value: trip.source == .automatic ? "Automatique" : "Manuel")
                LabeledContent("Points GPS", value: "\(trip.routePoints.count)")
            }
        }
        .navigationTitle("Détail du trajet")
        .sheet(isPresented: $isPresentingVehiclePicker) {
            VehiclePickerView(selectedVehicle: trip.vehicle) { vehicle in
                trip.vehicle = vehicle
                try? modelContext.save()
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Ma voiture")
    container.mainContext.insert(vehicle)
    let trip = Trip(startDate: .now.addingTimeInterval(-1800), source: .manual, vehicle: vehicle)
    trip.endDate = .now
    trip.distanceMeters = 12500
    container.mainContext.insert(trip)
    return NavigationStack {
        TripDetailView(trip: trip)
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
