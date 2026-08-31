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
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @State private var draft = VehicleDraft()

    var body: some View {
        NavigationStack {
            Form {
                VehicleFormFields(draft: $draft)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .localizedNavigationTitle("Nouveau véhicule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Voir PersonalDataView : clé explicite, parce que le mot
                    // « Enregistrer » couvre deux sens différents dans l'app.
                    Button(String(localized: "action.save", defaultValue: "Enregistrer", bundle: localizationBundle, locale: locale)) {
                        viewModel.addVehicle(draft, in: modelContext)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}

#Preview {
    AddVehicleView(viewModel: VehicleListViewModel(vehicleService: VehicleService()))
        .modelContainer(for: [Trip.self, Vehicle.self], inMemory: true)
}
