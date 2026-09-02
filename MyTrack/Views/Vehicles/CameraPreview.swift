//
//  CameraPreview.swift
//  MyTrack
//
//  L'appareil photo de l'app : la session, l'aperçu, le déclenchement.
//
//  Une session AVFoundation plutôt que `UIImagePickerController`, qui aurait
//  suffi à prendre une photo mais pas à poser la silhouette de guidage
//  par-dessus l'aperçu — et c'est elle qui décide de la qualité du détourage.
//
//  Rien ne démarre tout seul : la vue appelle `start()` en paraissant et
//  `stop()` en partant. Une session laissée tourner garde la caméra allumée et
//  la pastille verte avec.
//

import AVFoundation
import SwiftUI

@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    /// Ce que l'aperçu affiche. Nue au premier affichage : c'est `start()` qui
    /// la garnit, une fois l'autorisation obtenue.
    let session = AVCaptureSession()

    /// Faux tant qu'aucune caméra n'a pu être branchée — un simulateur, ou une
    /// autorisation refusée. L'écran propose alors la photothèque.
    private(set) var isReady = false

    private let output = AVCapturePhotoOutput()
    /// La session se configure et démarre hors du fil principal : `startRunning`
    /// bloque le temps que la caméra s'ouvre, et l'interface se figerait avec.
    private let queue = DispatchQueue(label: "MyTrack.camera")
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

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
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// La photo prise, une fois que le capteur a rendu sa copie.
    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            queue.async { [output] in
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output)
        else { return false }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        return true
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation = captureContinuation
        captureContinuation = nil
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            continuation?.resume(returning: image)
        } else {
            continuation?.resume(throwing: VehiclePhotoError.processingFailed)
        }
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
        // La caméra remplit le cadre quitte à déborder : des bandes noires
        // fausseraient le jugement de cadrage que la silhouette demande.
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
