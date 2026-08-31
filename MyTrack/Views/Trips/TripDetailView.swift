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
    @Environment(\.locale) private var locale
    @State private var isPresentingVehiclePicker = false
    @State private var isPresentingVehicleEditor = false

    private var sourceLabel: LocalizedStringKey {
        trip.source == .automatic ? "Automatique" : "Manuel"
    }

    var body: some View {
        List {
            Section("Trajet") {
                LabeledContent("Début", value: TripFormatting.dateAndTime(trip.startDate, locale: locale))
                if let endDate = trip.endDate {
                    LabeledContent("Fin", value: TripFormatting.dateAndTime(endDate, locale: locale))
                }
                LabeledContent("Durée", value: trip.formattedDuration(locale: locale))
                LabeledContent(
                    "Distance",
                    value: trip.formattedDistance(
                        in: appServices.unitSettingsService.distanceUnit, locale: locale
                    )
                )
            }
            costSection
            Section("Détails") {
                Button {
                    isPresentingVehiclePicker = true
                } label: {
                    HStack {
                        LabeledContent("Véhicule") {
                            if let name = trip.vehicle?.name {
                                Text(name)
                            } else {
                                Text("Aucun véhicule")
                            }
                        }
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                LabeledContent("Source") {
                    Text(sourceLabel)
                }
                LabeledContent("Points GPS") {
                    Text(trip.routePoints.count, format: .number)
                }
            }
            Section("Itinéraire") {
                TripRouteMapView(routePoints: trip.routePoints)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
        }
        .appBackground()
        .localizedNavigationTitle("Détail du trajet")
        .sheet(isPresented: $isPresentingVehiclePicker) {
            VehiclePickerView(selectedVehicle: trip.vehicle) { vehicle in
                trip.assignVehicle(vehicle)
                modelContext.saveOrLog()
            }
        }
        .sheet(isPresented: $isPresentingVehicleEditor) {
            if let vehicle = trip.vehicle {
                EditVehicleView(vehicle: vehicle)
            }
        }
    }

    /// Ce que le trajet a coûté, et de quoi ce chiffre est tiré : la
    /// consommation du véhicule, puis l'énergie qu'il en découle pour cette
    /// distance. Le détail plutôt que le seul montant, parce qu'un coût estimé
    /// qu'on ne peut pas refaire de tête n'inspire aucune confiance.
    ///
    /// Rien tant qu'aucun véhicule n'est associé : c'est lui qui porte la
    /// consommation, et la ligne « Véhicule » juste en dessous est déjà là pour
    /// en choisir un. S'il en manque une partie, la section mène à sa fiche
    /// plutôt que de rester une promesse vide.
    @ViewBuilder
    private var costSection: some View {
        if trip.vehicle != nil {
            // Un en-tête en fermeture plutôt qu'en chaîne : `Section(_:)` et
            // `footer:` ne se combinent pas, il n'existe pas d'initialiseur qui
            // prenne les deux.
            Section {
                if let consumption = trip.formattedConsumption(locale: locale) {
                    LabeledContent("Consommation", value: consumption)
                }
                if let price = trip.formattedEnergyPrice(locale: locale) {
                    LabeledContent("Prix", value: price)
                }
                if let energyUsed = trip.formattedEnergyUsed(locale: locale) {
                    LabeledContent("Énergie", value: energyUsed)
                }
                if let cost = trip.formattedEnergyCost(locale: locale) {
                    LabeledContent("Coût", value: cost)
                } else {
                    Button("Compléter la fiche du véhicule") {
                        isPresentingVehicleEditor = true
                    }
                }
            } header: {
                Text("Coût")
            } footer: {
                if trip.energyCost != nil {
                    Text("Estimation d'après les chiffres du véhicule au moment du trajet.")
                }
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
