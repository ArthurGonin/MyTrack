//
//  VehicleToolbarButton.swift
//  MyTrack
//
//  Le sélecteur de véhicule posé au centre de la barre de navigation : sur
//  l'écran d'accueil, où il désigne le véhicule qu'on conduit, et dans la liste
//  des trajets, où il filtre ce qu'on regarde. Un seul type pour les deux — ils
//  ouvrent la même feuille, ils doivent se lire pareil.
//
//  Le nom et la plaque se centrent ; le chevron, lui, n'entre pas dans ce
//  centrage. Il est doublé d'une copie invisible posée de l'autre côté du nom :
//  les deux se compensent, donc le nom tombe au milieu de la barre et la plaque
//  reste dans son axe, alors qu'un chevron seul à droite les décalerait tous
//  les deux vers la gauche de sa demi-largeur.
//

import SwiftUI

struct VehicleToolbarButton: View {
    /// Le véhicule montré, ou nil quand il n'y en a pas à montrer.
    let vehicle: Vehicle?
    /// Ce qui s'écrit alors à la place du nom : « Aucun véhicule » sur
    /// l'accueil, « Tous les véhicules » dans la liste des trajets.
    let placeholder: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    chevron.hidden()
                    name.font(.headline)
                    chevron
                }
                if let plate = vehicle?.licensePlate {
                    Text(plate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    /// Le nom d'un véhicule est une donnée saisie : il se rend tel quel, alors
    /// que le texte de remplacement, lui, se traduit. Un `??` les mélangerait
    /// en une `String` que SwiftUI rendrait sans traduire.
    @ViewBuilder
    private var name: some View {
        if let name = vehicle?.name {
            Text(name)
        } else {
            Text(placeholder)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.caption2)
    }
}

#Preview {
    NavigationStack {
        Text(verbatim: "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VehicleToolbarButton(vehicle: nil, placeholder: "Tous les véhicules") {}
                }
            }
    }
}
