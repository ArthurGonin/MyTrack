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
//  La photo fait exception, et en bas de fiche : elle ne passe pas par le
//  brouillon. Le détourage se termine longtemps après que l'écran a été fermé,
//  et il écrit directement sur le véhicule — « Annuler » annule donc la saisie,
//  jamais la photo. C'est le bon sens : photographier sa voiture est un geste en
//  soi, pas un champ de formulaire en attente d'être validé.
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
    @State private var isPresentingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                VehicleFormFields(draft: $draft)
                photoSection
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
        // La carte se pose au bas de la fiche, qui reste lisible au-dessus
        // d'elle. Voir `VehiclePhotoCaptureView` pour le choix d'une
        // surimpression plutôt que d'une feuille.
        .overlay(alignment: .bottom) {
            if isPresentingCamera {
                VehiclePhotoCaptureView(vehicle: vehicle) {
                    withAnimation(VehiclePhotoCaptureView.motion) { isPresentingCamera = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    /// La photo du véhicule, telle qu'elle sortira sur l'accueil, et de quoi la
    /// refaire.
    ///
    /// En bas de la fiche parce que c'est l'ordre de lecture : on renseigne
    /// d'abord ce que l'app calcule — le nom, l'énergie, la consommation — et
    /// l'illustration vient après. Elle s'affiche sur le fond du formulaire
    /// sans cadre : le PNG est détouré, il n'a rien derrière lui à masquer.
    @ViewBuilder
    private var photoSection: some View {
        Section("Photo") {
            if let data = vehicle.photoData, let photo = UIImage(data: data) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .accessibilityLabel("Photo du véhicule")
            }

            Button {
                withAnimation(VehiclePhotoCaptureView.motion) { isPresentingCamera = true }
            } label: {
                Label(
                    vehicle.photoData == nil ? "Photographier le véhicule" : "Reprendre la photo",
                    systemImage: "camera"
                )
            }

            if vehicle.photoData != nil {
                Button("Supprimer la photo", systemImage: "trash", role: .destructive) {
                    vehicle.photoData = nil
                    modelContext.saveOrLog()
                }
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
