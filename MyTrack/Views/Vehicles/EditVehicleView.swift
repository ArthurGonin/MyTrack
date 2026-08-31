//
//  EditVehicleView.swift
//  MyTrack
//
//  La fiche d'un véhicule déjà enregistré, ouverte depuis la liste des
//  véhicules. Mêmes champs que l'ajout — ils viennent du même `VehicleFormFields` —
//  mais posés sur un véhicule qui existe déjà.
//
//  La saisie passe par un brouillon plutôt que par des liaisons directes sur le
//  `@Model`, pour la même raison que PersonalDataView : avec un bouton
//  « Enregistrer » à l'écran, fermer sans enregistrer doit vraiment tout
//  annuler, ce qu'une liaison sur le modèle ne permet pas.
//

import SwiftUI
import SwiftData

struct EditVehicleView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @State private var draft = VehicleDraft()
    @State private var hasLoadedDraft = false

    var body: some View {
        NavigationStack {
            Form {
                VehicleFormFields(draft: $draft)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            // Le nom du véhicule, pas un titre traduit : c'est une donnée
            // saisie, elle se rend telle quelle — et « Modifier le véhicule »
            // se faisait couper entre les deux boutons de la barre.
            .navigationTitle(vehicle.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Voir PersonalDataView : clé explicite, parce que le mot
                    // « Enregistrer » couvre deux sens différents dans l'app.
                    Button(String(localized: "action.save", defaultValue: "Enregistrer", bundle: localizationBundle, locale: locale)) {
                        save()
                    }
                    .disabled(!draft.isValid)
                }
            }
            // Chargé une seule fois : la vue se reconstruit à chaque frappe, et
            // relire le véhicule à chaque passage effacerait ce qui vient
            // d'être tapé.
            .onAppear {
                guard !hasLoadedDraft else { return }
                draft = VehicleDraft(vehicle: vehicle, locale: locale)
                hasLoadedDraft = true
            }
        }
    }

    private func save() {
        draft.apply(to: vehicle)
        modelContext.saveOrLog()
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(
        name: "Clio",
        licensePlate: "AB-123-CD",
        energyType: .combustion,
        consumption: 6.5,
        energyPrice: 1.85
    )
    container.mainContext.insert(vehicle)

    return EditVehicleView(vehicle: vehicle)
        .modelContainer(container)
}
