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
    /// La ligne « Photographier » grandit en l'écran d'appareil photo, et
    /// rétrécit pour revenir — la transition `.zoom` du système, la même que
    /// depuis la vignette de la liste des véhicules.
    @Namespace private var photoTransition

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
            .fullScreenCover(isPresented: $isPresentingCamera) {
                VehiclePhotoCaptureView(vehicle: vehicle)
                    .navigationTransition(
                        .zoom(sourceID: vehicle.persistentModelID, in: photoTransition)
                    )
            }
            // Sur le formulaire et non sur la pile : sur la pile, la pastille
            // se lirait par-dessus le nom du véhicule. Et ici en plus de la
            // racine de l'app, parce que c'est cette fiche qu'on retrouve en
            // sortant de l'appareil photo — une surimpression posée dessous ne
            // traverserait pas la feuille.
            .vehiclePhotoToast()
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
                isPresentingCamera = true
            } label: {
                Label(
                    vehicle.photoData == nil ? "Photographier le véhicule" : "Reprendre la photo",
                    systemImage: "camera"
                )
            }
            .matchedTransitionSource(id: vehicle.persistentModelID, in: photoTransition)

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
