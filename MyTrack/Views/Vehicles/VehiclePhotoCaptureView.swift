//
//  VehiclePhotoCaptureView.swift
//  MyTrack
//
//  L'écran qui prend le véhicule en photo et attend que l'IA le détoure.
//
//  Deux temps, pas trois : on cadre, on déclenche, et la photo reste à l'écran
//  sous le voile d'analyse jusqu'à ce que le résultat soit rangé sur le
//  véhicule. Pas d'écran de validation entre les deux — un détourage raté se
//  reprend depuis la liste des véhicules, en touchant la vignette.
//
//  La silhouette de guidage est l'illustration de l'accueil elle-même, posée en
//  transparence : elle montre exactement le cadrage visé — la voiture de face,
//  occupant la largeur — et elle suivra le dessin si celui-ci change un jour.
//
//  Sans appareil photo — le simulateur — la photothèque prend le relais. Ce
//  n'est pas qu'une commodité de développement : c'est aussi la porte de sortie
//  de quelqu'un qui a déjà une bonne photo de sa voiture.
//

import PhotosUI
import SwiftUI

struct VehiclePhotoCaptureView: View {
    let vehicle: Vehicle

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraController()
    /// Non nil dès le déclenchement : c'est lui qui fait passer l'écran du
    /// cadrage à l'analyse.
    @State private var capturedPhoto: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var failure: Failure?

    /// Ce qui a pu manquer, dit à l'utilisateur plutôt qu'au journal. Le
    /// distinguo compte : « réessayez demain » et « recadrez la voiture » ne
    /// demandent pas le même geste.
    private enum Failure: Int, Identifiable {
        case notConfigured
        case unavailable
        case quotaReached
        case processing

        var id: Int { rawValue }

        init(_ error: Error) {
            switch error {
            case VehiclePhotoError.notConfigured: self = .notConfigured
            case VehiclePhotoError.serviceUnavailable: self = .unavailable
            case VehiclePhotoError.quotaReached: self = .quotaReached
            default: self = .processing
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .notConfigured: "La retouche photo n'est pas disponible."
            case .unavailable: "Le service n'a pas répondu."
            case .quotaReached: "Vous avez atteint la limite de photos du jour."
            case .processing: "La photo n'a pas pu être traitée."
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .notConfigured: "Le service qui détoure les photos n'est pas configuré dans cette version."
            case .unavailable: "Vérifiez votre connexion, puis réessayez dans un instant."
            case .quotaReached: "Réessayez demain."
            case .processing: "Reculez un peu, cadrez le véhicule de face, et réessayez."
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let capturedPhoto {
                analysing(capturedPhoto)
            } else {
                framing
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await loadFromLibrary(item) }
        }
        .alert(item: $failure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.message),
                dismissButton: .default(Text("Réessayer"))
            )
        }
    }

    // MARK: - Cadrage

    private var framing: some View {
        ZStack {
            if camera.isReady {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                // Remonté : centré, il se posait en plein milieu de la
                // silhouette et les deux se lisaient l'un sur l'autre.
                noCameraPlaceholder
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 140)
            }

            Image("HomeCar")
                .resizable()
                .scaledToFit()
                .opacity(0.22)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Le bouton et la consigne dans la même pile, l'un sous
                // l'autre : posé en surimpression, « Annuler » venait se
                // superposer au texte.
                HStack {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text("Placez le véhicule dans la silhouette, vu de face.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.35), in: .capsule)
                    .padding(.top, 16)

                Spacer()
                controls
            }
        }
    }

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $libraryItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel("Choisir une photo")

            Spacer()

            if camera.isReady {
                Button {
                    Task { await capture() }
                } label: {
                    // Le déclencheur des appareils photo d'iOS : un disque blanc
                    // cerclé de blanc. Personne n'a besoin qu'on lui explique.
                    Circle()
                        .fill(.white)
                        .frame(width: 66, height: 66)
                        .overlay {
                            Circle().stroke(.white, lineWidth: 3).frame(width: 78, height: 78)
                        }
                }
                .accessibilityLabel("Prendre la photo")
            }

            Spacer()
            // Le pendant du bouton de gauche : la place se garde pour que le
            // déclencheur reste au milieu de l'écran.
            Color.clear.frame(width: 56, height: 56)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
    }

    private var noCameraPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.6))
            Text("L'appareil photo n'est pas disponible ici.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Analyse

    private func analysing(_ photo: UIImage) -> some View {
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(.black.opacity(0.25))
            PhotoAnalysisOverlay().ignoresSafeArea()
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Analyse du véhicule…")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.4), in: .capsule)
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Enchaînement

    private func capture() async {
        do {
            process(try await camera.capturePhoto())
        } catch {
            failure = Failure(error)
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let photo = UIImage(data: data)
        else {
            failure = .processing
            return
        }
        process(photo)
    }

    /// La photo passe à l'analyse, et n'en revient que rangée sur le véhicule.
    private func process(_ photo: UIImage) {
        capturedPhoto = photo
        Task {
            do {
                let data = try await appServices.vehiclePhotoService.processedPhoto(from: photo)
                vehicle.photoData = data
                modelContext.saveOrLog()
                dismiss()
            } catch {
                // Retour au cadrage : l'alerte se lit par-dessus l'aperçu, et le
                // déclencheur est déjà sous le pouce pour reprendre le cliché.
                capturedPhoto = nil
                failure = Failure(error)
            }
        }
    }
}
