//
//  VehiclePickerView.swift
//  MyTrack
//
//  Reusable "pick a vehicle" sheet. What selecting a row actually means is
//  left to the caller via `onSelect` — RecordTripView uses it to change the
//  globally active vehicle, TripDetailView uses it to reassign a single past
//  trip, and neither has to know about the other's meaning of "selected".
//

import SwiftUI
import SwiftData

struct VehiclePickerView: View {
    let selectedVehicle: Vehicle?
    let onSelect: (Vehicle) -> Void

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]
    @State private var isPresentingAddVehicle = false

    private var viewModel: VehicleListViewModel {
        VehicleListViewModel(vehicleService: appServices.vehicleService)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vehicles.isEmpty {
                    ContentUnavailableView(
                        "Aucun véhicule",
                        systemImage: "car",
                        description: Text("Ajoute un véhicule pour l'associer à tes trajets.")
                    )
                } else {
                    List {
                        ForEach(vehicles) { vehicle in
                            Button {
                                onSelect(vehicle)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(vehicle.name)
                                        if let plate = vehicle.licensePlate {
                                            Text(plate)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if vehicle === selectedVehicle {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteVehicle(vehicles[index], in: modelContext)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Véhicules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddVehicle) {
                AddVehicleView(viewModel: viewModel)
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return VehiclePickerView(selectedVehicle: nil, onSelect: { _ in })
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
