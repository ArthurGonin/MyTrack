//
//  VehiclePhotoCaptureView.swift
//  MyTrack
//
//  L'écran qui prend le véhicule en photo. Il ne fait plus que ça.
//
//  Un seul temps désormais : on cadre, on déclenche, l'écran se referme. Le
//  détourage se poursuit sans lui — voir `VehiclePhotoProcessingService` — et
//  se raconte dans une pastille en haut de l'app. Il n'y a donc plus d'écran
//  d'attente : dix à trente secondes devant un voile animé, c'est dix à trente
//  secondes pendant lesquelles l'app est prise en otage pour une photo de
//  voiture.
//
//  L'aperçu est une carte à coins arrondis posée sur du noir, au format exact
//  du cliché (3:4, celui de `sessionPreset = .photo`). Ce format n'est pas une
//  coquetterie : plein écran, l'aperçu rognait ce que le capteur voyait
//  vraiment, et on cadrait donc à l'aveugle une photo plus large que ce qu'on
//  avait sous les yeux. Ici, ce qu'on voit est ce qui part.
//
//  Plus de silhouette de voiture en surimpression. Elle salissait l'aperçu
//  pour redire ce que la situation dit déjà : on photographie une voiture, on
//  se met devant. Une ligne de texte au-dessus de la carte suffit à préciser
//  « de face », et elle ne recouvre rien.
//
//  Les trois commandes sont des pastilles de verre posées dans le bas de
//  l'aperçu : fermer à gauche, déclencher au centre, flash et photothèque à
//  droite. Le déclencheur est dans une pile à part pour rester au milieu de la
//  carte quoi qu'il arrive à ses voisins — un côté à un bouton, l'autre à deux,
//  une rangée simple l'aurait décalé.
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
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraController()
    @State private var libraryItem: PhotosPickerItem?
    @State private var hasCaptureFailed = false
    /// Monte à chaque déclenchement, pour que le doigt sente la prise. La photo
    /// elle-même ne se voit pas partir : l'écran se ferme dans la seconde.
    @State private var shutterCount = 0

    /// La marge autour de la carte, et l'arrondi de ses coins.
    private static let margin: CGFloat = 10
    private static let corner: CGFloat = 34
    /// Le format d'un cliché : `sessionPreset = .photo` rend du 3:4, et
    /// l'aperçu le prend tel quel.
    private static let aspectRatio: CGFloat = 3.0 / 4.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                caption
                viewfinder
            }
            .padding(.horizontal, Self.margin)
            .padding(.bottom, Self.margin)
        }
        // L'écran est noir de bout en bout : l'heure et la batterie doivent
        // s'écrire en blanc, et le verre des pastilles se teinter pour du sombre.
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await loadFromLibrary(item) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterCount)
        // Sans bouton déclaré, SwiftUI en pose un « OK » traduit par le
        // système. Il n'y a rien d'autre à proposer : on est déjà devant
        // l'appareil photo, reprendre est un appui sur le déclencheur.
        .alert("La photo n'a pas pu être prise.", isPresented: $hasCaptureFailed) {}
    }

    // MARK: - Cadrage

    /// Le nom du véhicule, puis la consigne : de quoi savoir laquelle de ses
    /// voitures on est en train de photographier, ce qu'un écran sans barre de
    /// navigation ne dit nulle part ailleurs. Les deux ensemble, juste au-dessus
    /// de la carte, plutôt que chacun perdu dans le noir.
    private var caption: some View {
        VStack(spacing: 3) {
            Text(vehicle.name)
                .font(.headline)
                .foregroundStyle(.white)
            Text("Cadrez le véhicule de face.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
    }

    private var viewfinder: some View {
        ZStack {
            if camera.isReady {
                CameraPreview(session: camera.session)
            } else {
                Color(white: 0.11)
                noCameraPlaceholder
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Self.corner, style: .continuous))
        // Posées après le rognage, donc jamais coupées par le coin : l'anneau
        // du déclencheur déborde de sa pastille.
        .overlay(alignment: .bottom) { controls }
    }

    private var controls: some View {
        ZStack {
            if camera.isReady {
                shutter
            }
            HStack(spacing: 0) {
                Button { dismiss() } label: { symbol("xmark") }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Fermer l'appareil photo")

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if camera.hasFlash {
                        flashButton
                    }
                    libraryButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// Le déclencheur des appareils photo d'iOS : un disque blanc cerclé de
    /// blanc. Personne n'a besoin qu'on lui explique.
    private var shutter: some View {
        Button {
            shutterCount += 1
            Task { await capture() }
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 62, height: 62)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.85), lineWidth: 3)
                        .frame(width: 74, height: 74)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Prendre la photo")
    }

    /// Éteint par défaut, et non « automatique » comme dans l'appareil photo du
    /// système : un flash sur une carrosserie fait exactement les reflets que le
    /// détourage passe ensuite son temps à effacer. Il reste là pour un garage
    /// mal éclairé, mais il faut le vouloir.
    private var flashButton: some View {
        Button {
            camera.isFlashOn.toggle()
        } label: {
            symbol(
                camera.isFlashOn ? "bolt.fill" : "bolt.slash.fill",
                tint: camera.isFlashOn ? .yellow : .white
            )
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(camera.isFlashOn ? "Désactiver le flash" : "Activer le flash")
    }

    /// Un `PhotosPicker` n'est pas un `Button` : le verre s'habille autour du
    /// symbole plutôt que de se poser sur le bouton, comme pour les deux autres.
    private var libraryButton: some View {
        PhotosPicker(selection: $libraryItem, matching: .images) {
            symbol("photo.on.rectangle")
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Choisir une photo")
    }

    private func symbol(_ systemName: String, tint: Color = .white) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
    }

    private var noCameraPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text("L'appareil photo n'est pas disponible ici.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Enchaînement

    private func capture() async {
        do {
            hand(try await camera.capturePhoto())
        } catch {
            hasCaptureFailed = true
        }
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let photo = UIImage(data: data)
        else {
            hasCaptureFailed = true
            return
        }
        hand(photo)
    }

    /// La photo confiée au service, et l'écran refermé dans la foulée.
    ///
    /// Dans cet ordre et sans rien attendre entre les deux : le détourage dure
    /// dix à trente secondes, et c'est justement ce qu'on ne fait plus attendre.
    /// Ce qu'il en advient se dit dans une pastille, où que soit l'utilisateur.
    private func hand(_ photo: UIImage) {
        appServices.vehiclePhotoProcessingService.process(photo, for: vehicle)
        dismiss()
    }
}
