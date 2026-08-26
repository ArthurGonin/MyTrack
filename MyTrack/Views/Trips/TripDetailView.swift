//
//  TripDetailView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices
    @State private var isPresentingVehiclePicker = false

    var body: some View {
        List {
            Section("Trajet") {
                LabeledContent("Début", value: trip.startDate.formatted(date: .abbreviated, time: .shortened))
                if let endDate = trip.endDate {
                    LabeledContent("Fin", value: endDate.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Durée", value: trip.formattedDuration)
                LabeledContent(
                    "Distance",
                    value: trip.formattedDistance(in: appServices.unitSettingsService.distanceUnit)
                )
            }
            Section("Détails") {
                Button {
                    isPresentingVehiclePicker = true
                } label: {
                    HStack {
                        LabeledContent("Véhicule", value: trip.vehicle?.name ?? "Aucun véhicule")
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                LabeledContent("Source", value: trip.source == .automatic ? "Automatique" : "Manuel")
                LabeledContent("Points GPS", value: "\(trip.routePoints.count)")
            }
            Section("Itinéraire") {
                TripRouteMapView(routePoints: trip.routePoints)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle("Détail du trajet")
        .sheet(isPresented: $isPresentingVehiclePicker) {
            VehiclePickerView(selectedVehicle: trip.vehicle) { vehicle in
                trip.vehicle = vehicle
                modelContext.saveOrLog()
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
    trip.routePoints = [
        RoutePoint(latitude: 48.8584, longitude: 2.2945, timestamp: .now.addingTimeInterval(-1800)),
        RoutePoint(latitude: 48.8620, longitude: 2.3050, timestamp: .now.addingTimeInterval(-1200)),
        RoutePoint(latitude: 48.8670, longitude: 2.3170, timestamp: .now.addingTimeInterval(-600)),
        RoutePoint(latitude: 48.8710, longitude: 2.3280, timestamp: .now)
    ]
    container.mainContext.insert(trip)
    return NavigationStack {
        TripDetailView(trip: trip)
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
