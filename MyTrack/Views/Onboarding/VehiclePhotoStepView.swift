//
//  VehiclePhotoStepView.swift
//  MyTrack
//
//  L'étape qui propose de photographier sa voiture, juste après l'avoir nommée.
//
//  Elle a son propre bouton plutôt que le « Continuer » partagé : ce qu'on fait
//  ici n'est pas tourner la page, c'est ouvrir l'appareil photo. Le bouton porte
//  donc le style du « Continuer » au détail près — même verre, même taille, même
//  largeur — pour que ce soit visiblement le même bouton, qui fait autre chose.
//
//  Facultative, et le bouton « Passer » en haut le dit. La voiture dessinée de
//  l'accueil prend le relais quand il n'y a pas de photo, et l'app fonctionne
//  aussi bien.
//

import SwiftUI
import UIKit

struct VehiclePhotoStepView: View {
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Une photo de votre voiture")
                    .font(.largeTitle.bold())
                Text("Elle sera détourée, puis posée sur votre écran d'accueil.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
            illustration
            Spacer(minLength: 0)

            // Aucune marge horizontale ici, contrairement au titre : le bouton
            // doit tomber sur la même largeur que le « Continuer » des autres
            // étapes, qui ne connaît que la marge de l'onboarding.
            Button {
                onTakePhoto()
            } label: {
                Text("Prendre en photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onAccent)
            .glassEffect(.clear.interactive())
            .controlSize(.large)
        }
    }

    /// Le dessin du milieu : quelqu'un qui photographie sa voiture.
    ///
    /// Il n'est pas encore là. En attendant, c'est la voiture de l'accueil qui
    /// tient la place — elle a au moins le mérite de montrer ce que la photo
    /// devient une fois détourée. Déposer un fichier nommé comme ci-dessous
    /// dans le catalogue d'assets suffit à le remplacer : rien à changer ici.
    private static let illustrationName = "OnboardingVehiclePhoto"

    @ViewBuilder
    private var illustration: some View {
        // `UIImage(named:)` plutôt que `Image(_:)` : SwiftUI rend une vue vide
        // quand la ressource manque, sans rien dire, et l'étape se serait
        // affichée avec un trou au milieu.
        if let drawing = UIImage(named: Self.illustrationName) ?? UIImage(named: "HomeCar") {
            Image(uiImage: drawing)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                // Le même débord que sur l'accueil : une voiture coupée par le
                // bord a l'air posée devant l'écran plutôt que dedans.
                .padding(.horizontal, -28)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    VehiclePhotoStepView(onTakePhoto: {})
        .padding()
        .appBackground()
}
