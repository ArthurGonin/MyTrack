//
//  AddVehicleView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct AddVehicleView: View {
    let viewModel: VehicleListViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var licensePlate = ""

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du véhicule", text: $name)
                TextField("Immatriculation (optionnel)", text: $licensePlate)
            }
            .navigationTitle("Nouveau véhicule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        viewModel.addVehicle(name: name, licensePlate: licensePlate, in: modelContext)
                        dismiss()
                    }
                    .disabled(!isNameValid)
                }
            }
        }
    }
}

#Preview {
    AddVehicleView(viewModel: VehicleListViewModel(vehicleService: VehicleService()))
        .modelContainer(for: [Trip.self, Vehicle.self], inMemory: true)
}
