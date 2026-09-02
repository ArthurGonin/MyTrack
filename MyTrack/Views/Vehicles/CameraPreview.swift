//
//  CameraPreview.swift
//  MyTrack
//
//  L'appareil photo de l'app : la session, l'aperçu, le déclenchement.
//
//  Une session AVFoundation plutôt que `UIImagePickerController`, qui aurait
//  suffi à prendre une photo mais pas à la cadrer dans une carte à nous, ni à
//  poser des pastilles de verre dans son aperçu, ni à choisir le flash.
//
//  Rien ne démarre tout seul : la vue appelle `start()` en paraissant et
//  `stop()` en partant. Une session laissée tourner garde la caméra allumée et
//  la pastille verte avec.
//
//  Le déclenchement se joue à deux : le contrôleur, qui vit sur le fil principal
//  comme tout ce qui touche à l'interface, et un délégué à part qui reçoit la
//  photo — parce qu'AVFoundation ne rappelle pas sur ce fil-là. Voir
//  `PhotoCaptureDelegate`.
//

// `@preconcurrency` : AVFoundation n'est pas encore annoté pour la concurrence
// stricte, et ses objets de session y passent pour impartageables alors qu'ils
// sont faits pour être menés depuis une file de service. Sans lui, la ligne qui
// confie la prise à `queue` se plaint de l'`AVCapturePhotoOutput` qu'elle
// emporte.
@preconcurrency import AVFoundation
import Synchronization
import SwiftUI

@Observable
final class CameraController {
    /// Ce que l'aperçu affiche. Nue au premier affichage : c'est `start()` qui
    /// la garnit, une fois l'autorisation obtenue.
    let session = AVCaptureSession()

    /// Faux tant qu'aucune caméra n'a pu être branchée — un simulateur, ou une
    /// autorisation refusée. L'écran propose alors la photothèque.
    private(set) var isReady = false

    /// Faux quand l'appareil n'a pas de flash — le simulateur, la caméra avant
    /// de certains modèles. Le bouton disparaît alors plutôt que de rester là
    /// sans effet.
    private(set) var hasFlash = false

    /// Le flash, tel que l'utilisateur l'a réglé. Éteint par défaut : voir le
    /// bouton dans `VehiclePhotoCaptureView`.
    var isFlashOn = false

    private let output = AVCapturePhotoOutput()
    /// La session se configure et démarre hors du fil principal : `startRunning`
    /// bloque le temps que la caméra s'ouvre, et l'interface se figerait avec.
    private let queue = DispatchQueue(label: "MyTrack.camera")

    /// Les prises en cours, chacune avec le délégué qui l'attend.
    ///
    /// C'est ici qu'elles tiennent en vie : `AVCapturePhotoOutput` ne retient
    /// son délégué que faiblement, et un délégué désalloué est une photo qui ne
    /// revient jamais — la pastille resterait sur « Traitement de la photo… »
    /// sans fin. Rangées sous l'identifiant que porte chaque réglage, pour que
    /// deux appuis rapprochés ne se chassent pas l'un l'autre.
    private var pendingCaptures: [Int64: PhotoCaptureDelegate] = [:]

    func start() async {
        // L'autorisation ne se demande qu'à un appareil qui a de quoi filmer :
        // sur un simulateur, la fenêtre s'ouvrirait pour rien et la photothèque
        // aurait pris le relais de toute façon.
        guard AVCaptureDevice.default(for: .video) != nil else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }
        guard !session.isRunning else { return }

        let configured = await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { return continuation.resume(returning: false) }
                continuation.resume(returning: self.configureSession())
            }
        }
        isReady = configured
        // Lu sur l'appareil plutôt que sur la sortie : `supportedFlashModes`
        // n'a de sens qu'une fois la prise engagée, alors que le bouton, lui,
        // doit savoir s'afficher tout de suite.
        hasFlash = configured && (AVCaptureDevice.default(for: .video)?.hasFlash ?? false)
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// La photo prise, une fois que le capteur a rendu sa copie.
    func capturePhoto() async throws -> UIImage {
        // Relevé ici, sur le fil principal, parce que c'est là qu'il vit : la
        // file de la session ne peut pas relire une propriété de l'interface.
        let wantsFlash = isFlashOn
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let identifier = settings.uniqueID
            let delegate = PhotoCaptureDelegate { [weak self] result in
                // Le délégué a fini de servir ; le contrôleur peut le lâcher.
                // Repris dans une constante d'abord : une référence faible reste
                // une variable, et une variable ne se relit pas depuis un autre
                // fil.
                if let self {
                    Task { @MainActor in self.pendingCaptures[identifier] = nil }
                }
                continuation.resume(with: result)
            }
            pendingCaptures[identifier] = delegate
            queue.async { [output] in
                // Le mode se pose ici et pas plus tôt : `supportedFlashModes`
                // se lit sur la sortie, donc sur cette file — et poser un mode
                // qui n'y est pas lève une exception qui ferme l'app.
                let mode: AVCaptureDevice.FlashMode = wantsFlash ? .on : .off
                if output.supportedFlashModes.contains(mode) {
                    settings.flashMode = mode
                }
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// La session montée, prête à tourner.
    ///
    /// Un `commitConfiguration` par chemin, et pas un de plus : la configuration
    /// se referme avant `startRunning`, qui lève une `NSGenericException` s'il en
    /// reste une d'ouverte (`AVCaptureSession.h`). C'est aussi pourquoi il n'y a
    /// pas de `defer` ici — il aurait fermé une seconde fois, après coup, ce qui
    /// était déjà refermé.
    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output)
        else {
            session.commitConfiguration()
            return false
        }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        return true
    }
}

/// Le receveur de la photo, tenu à part du contrôleur.
///
/// À part, parce qu'AVFoundation appelle ses méthodes « on a common dispatch
/// queue — not necessarily the main queue », dit l'en-tête d'`AVCapturePhotoOutput`.
/// Le contrôleur, lui, vit sur le fil principal : lui faire porter ces appels-là
/// était une course de données — deux fils sur la même continuation — et le mode
/// Swift 6 refuse d'ailleurs de la compiler.
///
/// `nonisolated` pour la même raison : sans ce mot, le projet le rattacherait au
/// fil principal comme tout le reste (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    /// Ce qu'il reste à faire de la photo, vidé au premier appel : reprendre
    /// deux fois la même continuation ferme l'app, et rien ne promet
    /// qu'AVFoundation n'appellera qu'une fois.
    private let pending: Mutex<(@Sendable (Result<UIImage, Error>) -> Void)?>

    init(onPhoto: @escaping @Sendable (Result<UIImage, Error>) -> Void) {
        pending = Mutex(onPhoto)
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<UIImage, Error> =
            if let error {
                .failure(error)
            } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
                .success(image)
            } else {
                .failure(VehiclePhotoError.processingFailed)
            }

        // Repris hors du verrou : ce que fait l'appelant ne doit pas se dérouler
        // pendant qu'il est tenu.
        let onPhoto = pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
        onPhoto?(result)
    }
}

/// L'aperçu lui-même. La couche d'AVFoundation est celle de la vue plutôt qu'une
/// sous-couche ajoutée à la main : elle suit alors les changements de taille
/// toute seule, sans avoir à la redimensionner à chaque rotation.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        // La carte qui accueille cet aperçu est au format du cliché, si bien
        // que « remplir » et « tenir dedans » reviennent au même. Remplir reste
        // le bon choix des deux : le jour où ce format bougerait, mieux vaut un
        // aperçu débordant qu'un aperçu bordé de noir.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
