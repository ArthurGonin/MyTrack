//
//  VehiclePhotoCaptureView.swift
//  MyTrack
//
//  L'appareil photo du véhicule : une carte qui monte par-dessus l'app.
//
//  Elle ne prend pas l'écran. L'app reste là, entière et vivante autour d'elle :
//  visible, non voilée, et toujours au doigt — la carte ne reçoit les touchers
//  que là où elle est. Prendre une photo de sa voiture ne justifie pas de faire
//  disparaître tout le reste.
//
//  Une surimpression et non une feuille, alors que la feuille serait le geste
//  système. Trois choses l'ont écartée : elle voile ce qu'elle recouvre (et
//  dévoiler, côté système, c'est la même manette que rendre traversable), elle
//  fait reculer et rétrécir la feuille d'où elle sort — la liste des véhicules
//  se serait mise à flotter en petit derrière l'appareil photo —, et elle
//  dessine son propre cadre, avec son ombre et son arrondi, sous celui de la
//  carte. Trois cadres pour une seule carte. Ici, ce qui est derrière ne bouge
//  pas d'un point.
//
//  Un seul temps : on cadre, on déclenche, la feuille redescend. Le détourage
//  se poursuit sans elle — voir `VehiclePhotoProcessingService` — et se raconte
//  dans une pastille en haut de l'app.
//
//  Elle descend jusqu'au bord de l'iPhone, et ses coins du bas épousent ceux
//  de l'écran : `ConcentricRectangle` prend l'arrondi du matériel et lui retire
//  la marge, de sorte que les deux courbes restent parallèles quel que soit
//  l'appareil. Un rayon écrit en dur aurait été juste sur un modèle et faux sur
//  tous les autres — et sur un iPhone à bouton, dont l'écran a des coins
//  droits, c'est le minimum demandé qui s'applique.
//
//  La carte est au format exact du cliché (3:4, celui de `sessionPreset =
//  .photo`). Ce n'est pas une coquetterie : plein écran, l'aperçu rognait ce
//  que le capteur voyait vraiment, et on cadrait donc à l'aveugle une photo
//  plus large que celle qu'on avait sous les yeux. Ici, ce qu'on voit est ce
//  qui part.
//
//  Rien par-dessus l'aperçu : ni silhouette de voiture, ni consigne, ni nom du
//  véhicule. On vient de toucher sa ligne, on sait de quelle voiture il s'agit,
//  et on a compris qu'on la photographie de face. Tout ce qui s'ajouterait là
//  salirait la seule chose qu'on est venu regarder.
//
//  Les commandes sont des pastilles de verre dans le bas de l'aperçu : fermer à
//  gauche, déclencher au centre, flash et photothèque à droite. Le déclencheur
//  est dans une pile à part pour rester au milieu de la carte quoi qu'il arrive
//  à ses voisins — un côté à un bouton, l'autre à deux, une rangée simple
//  l'aurait décalé.
//
//  Sans appareil photo — le simulateur — la photothèque prend le relais. Ce
//  n'est pas qu'une commodité de développement : c'est aussi la porte de sortie
//  de quelqu'un qui a déjà une bonne photo de sa voiture.
//

import PhotosUI
import SwiftUI

struct VehiclePhotoCaptureView: View {
    let vehicle: Vehicle
    /// Ce que fait l'écran hôte pour retirer la carte. À lui de l'animer : la
    /// carte ne connaît ni l'état qui la porte ni le ressort qui la remonte.
    let onClose: () -> Void

    @Environment(AppServices.self) private var appServices

    @State private var camera = CameraController()
    @State private var libraryItem: PhotosPickerItem?
    @State private var hasCaptureFailed = false
    /// Monte à chaque déclenchement, pour que le doigt sente la prise. La photo
    /// elle-même ne se voit pas partir : la carte redescend dans la seconde.
    @State private var shutterCount = 0
    /// Ce que le doigt a déjà emporté vers le bas. Rendu à zéro si on lâche
    /// trop tôt.
    @State private var dragOffset: CGFloat = 0

    /// La marge autour de la carte — la même en bas que sur les côtés, sans
    /// quoi les coins du bas ne pourraient pas rester parallèles à ceux de
    /// l'écran — et l'arrondi de ses coins du haut.
    private static let margin: CGFloat = 10
    private static let corner: CGFloat = 34
    /// Le format d'un cliché : `sessionPreset = .photo` rend du 3:4, et
    /// l'aperçu le prend tel quel.
    private static let aspectRatio: CGFloat = 3.0 / 4.0

    /// L'encoche du bas de l'écran, celle qu'il faut franchir pour aller
    /// toucher le bord.
    ///
    /// Lue sur la fenêtre, comme `TabBarMetrics` lit la barre d'onglets : une
    /// surimpression posée au bas d'un écran est disposée à l'intérieur de la
    /// zone sûre, et rien dans SwiftUI ne publie de combien. Zéro là où il n'y
    /// a pas d'encoche — un iPhone à bouton — et la carte y est déjà au bord.
    private static var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    /// Le ressort qui la fait monter et redescendre. Tenu ici, avec elle, pour
    /// que les deux écrans qui la posent la fassent apparaître de la même
    /// façon — sinon l'un des deux dérive au premier réglage.
    static let motion: Animation = .snappy(duration: 0.38)

    var body: some View {
        viewfinder
            .padding(.horizontal, Self.margin)
            .padding(.bottom, Self.margin)
            // Descendue jusqu'au bord du matériel, par-dessus la barre
            // d'accueil. Un décalage et non `ignoresSafeArea` : celui-ci
            // n'agit que sur une vue qui remplit son contenant, et la carte,
            // elle, a la taille que son format lui donne. Le décalage emporte
            // aussi la zone sensible au doigt, ce qu'il faut ici.
            .offset(y: Self.bottomInset + dragOffset)
            .gesture(dismissDrag)
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

    /// Ce qui a monté redescend en le poussant. Le geste qu'on fait sans y
    /// penser devant quelque chose qui est arrivé par le bas — et la croix
    /// reste là pour qui ne le fait pas.
    ///
    /// La vitesse compte autant que la distance : un coup sec et court referme,
    /// là où un glissement lent doit aller plus loin pour valoir décision.
    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = max(0, $0.translation.height) }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                    onClose()
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Cadrage

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
        .clipShape(Self.cardShape)
        // Posées après le rognage, donc jamais coupées par le coin : l'anneau
        // du déclencheur déborde de sa pastille.
        .overlay(alignment: .bottom) { controls }
        // Le verre et les symboles se règlent sur ce qu'ils recouvrent — une
        // image de caméra, sombre par nature — et non sur le thème de l'app.
        // En clair, un symbole blanc sur du verre clair ne se lirait plus.
        .environment(\.colorScheme, .dark)
    }

    /// Le haut à l'arrondi de l'app, le bas à celui de l'iPhone.
    ///
    /// `.concentric` lit l'arrondi du contenant — l'écran — et lui retire la
    /// marge, ce qui garde les deux courbes parallèles. Le minimum sert aux
    /// appareils dont l'écran n'est pas arrondi : les coins du bas y valent
    /// alors ceux du haut, plutôt que de se casser à angle droit.
    private static var cardShape: some Shape {
        ConcentricRectangle(
            uniformTopCorners: .fixed(corner),
            uniformBottomCorners: .concentric(minimum: .fixed(corner))
        )
    }

    private var controls: some View {
        ZStack {
            if camera.isReady {
                shutter
            }
            HStack(spacing: 0) {
                Button(action: onClose) { symbol("xmark") }
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

    /// La photo confiée au service, et la carte refermée dans la foulée.
    ///
    /// Dans cet ordre et sans rien attendre entre les deux : le détourage dure
    /// dix à trente secondes, et c'est justement ce qu'on ne fait plus attendre.
    /// Ce qu'il en advient se dit dans une pastille, où que soit l'utilisateur.
    private func hand(_ photo: UIImage) {
        appServices.vehiclePhotoProcessingService.process(photo, for: vehicle)
        onClose()
    }
}
