//
//  VehiclePhotoService.swift
//  MyTrack
//
//  De la photo prise par l'utilisateur au PNG détouré que l'accueil affiche.
//
//  Le travail est confié à un modèle d'images d'OpenAI, avec le prompt mis au
//  point pour ça : fond retiré, lumière de studio, reflets des vitres effacés,
//  trois-quarts redressé en face. Rien de tout cela ne se fait sur l'appareil —
//  iOS sait détacher un sujet de son fond, mais pas relever une carrosserie ni
//  nettoyer un pare-brise.
//
//  Deux voies pour l'atteindre : le proxy, qui détient la clé, et — en
//  compilation Debug seulement — un appel direct pour essayer sans rien
//  déployer. Voir `StudioCutoutConfiguration`.
//
//  Ce qui revient passe ensuite par le normalisateur : le modèle cadre au
//  jugé, et c'est le code qui garantit que toutes les voitures se posent au
//  même endroit du cadre.
//

import Foundation
import OSLog
import UIKit

/// Ce qui peut manquer en chemin. Sans texte : c'est la vue qui parle, elle
/// seule connaît la langue de l'app.
enum VehiclePhotoError: Error {
    /// Ni proxy ni clé d'essai : il n'y a personne à qui envoyer la photo.
    case notConfigured
    /// Le service n'a pas répondu, ou pas à temps.
    case serviceUnavailable
    /// Le plafond du jour est atteint.
    case quotaReached
    case processingFailed
}

final class VehiclePhotoService {
    /// La photo, détourée par le service puis remise au cadre commun, prête à
    /// être rangée sur le véhicule.
    func processedPhoto(from photo: UIImage) async throws -> Data {
        guard let source = Self.upright(photo) else { throw VehiclePhotoError.processingFailed }

        let cutout = try await studioCutout(from: source)
        let normalized = await Task.detached(priority: .userInitiated) {
            VehiclePhotoNormalizer.normalized(cutout)
        }.value
        guard let normalized, let data = UIImage(cgImage: normalized).pngData() else {
            throw VehiclePhotoError.processingFailed
        }
        return data
    }

    // MARK: - Le service

    private func studioCutout(from image: CGImage) async throws -> CGImage {
        guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            throw VehiclePhotoError.processingFailed
        }

        if StudioCutoutConfiguration.isConfigured {
            return try await viaProxy(jpeg)
        }
        #if DEBUG
        if StudioCutoutConfiguration.hasDebugKey {
            return try await directlyFromOpenAI(jpeg)
        }
        #endif
        throw VehiclePhotoError.notConfigured
    }

    /// Le chemin de production : le proxy rend le PNG déjà détouré.
    private func viaProxy(_ jpeg: Data) async throws -> CGImage {
        guard let url = StudioCutoutConfiguration.endpointURL else {
            throw VehiclePhotoError.notConfigured
        }
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            StudioCutoutConfiguration.sharedSecret, forHTTPHeaderField: "X-MyTrack-Secret"
        )
        // Ce que le proxy compte pour plafonner : un appareil, pas une personne.
        request.setValue(
            await UIDevice.current.identifierForVendor?.uuidString ?? "inconnu",
            forHTTPHeaderField: "X-MyTrack-Device"
        )
        request.httpBody = Self.multipartBody(
            boundary: boundary, parts: [.file(name: "photo", jpeg: jpeg)]
        )

        let (data, response) = try await Self.send(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw VehiclePhotoError.serviceUnavailable
        }
        if status == 429 { throw VehiclePhotoError.quotaReached }
        guard status == 200, let image = UIImage(data: data)?.cgImage else {
            throw VehiclePhotoError.serviceUnavailable
        }
        return image
    }

    #if DEBUG
    /// Le chemin d'essai : l'app parle à OpenAI elle-même, avec une clé posée à
    /// la main. Absent des compilations Release — voir
    /// `StudioCutoutConfiguration`.
    private func directlyFromOpenAI(_ jpeg: Data) async throws -> CGImage {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue(
            "Bearer \(StudioCutoutConfiguration.debugOpenAIKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            parts: [
                .field(name: "model", value: "gpt-image-1"),
                .file(name: "image", jpeg: jpeg),
                .field(name: "prompt", value: StudioCutoutConfiguration.prompt),
                .field(name: "size", value: "1536x1024"),
                .field(name: "background", value: "transparent"),
                .field(name: "output_format", value: "png"),
                .field(name: "quality", value: "high"),
                .field(name: "n", value: "1"),
            ]
        )

        let (data, response) = try await Self.send(request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw VehiclePhotoError.serviceUnavailable
        }
        guard status == 200 else {
            // Le message d'OpenAI vaut la peine d'être lu : c'est lui qui dit si
            // un paramètre a changé de nom depuis que ce code a été écrit.
            AppLog.recording.error(
                "Studio refusé (\(status, privacy: .public)) : \(String(data: data, encoding: .utf8) ?? "", privacy: .public)"
            )
            throw status == 429 ? VehiclePhotoError.quotaReached : VehiclePhotoError.serviceUnavailable
        }

        struct Payload: Decodable {
            struct Image: Decodable { let b64_json: String? }
            let data: [Image]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let base64 = payload.data.first?.b64_json,
              let bytes = Data(base64Encoded: base64),
              let image = UIImage(data: bytes)?.cgImage
        else { throw VehiclePhotoError.processingFailed }
        return image
    }
    #endif

    // MARK: - Plomberie HTTP

    /// Trente secondes ne suffisent pas toujours : un modèle d'images met dix à
    /// trente secondes en temps ordinaire, et davantage sous charge.
    private static let timeout: TimeInterval = 120

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw VehiclePhotoError.serviceUnavailable
        }
    }

    private enum MultipartPart {
        case field(name: String, value: String)
        case file(name: String, jpeg: Data)
    }

    private static func multipartBody(boundary: String, parts: [MultipartPart]) -> Data {
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            switch part {
            case let .field(name, value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                body.append(value.data(using: .utf8)!)
            case let .file(name, jpeg):
                body.append(
                    "Content-Disposition: form-data; name=\"\(name)\"; filename=\"photo.jpg\"\r\n"
                        .data(using: .utf8)!
                )
                body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                body.append(jpeg)
            }
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Préparation

    /// La photo redressée et ramenée à une taille raisonnable.
    ///
    /// Redressée parce qu'un cliché d'appareil photo porte son orientation dans
    /// une étiquette plutôt que dans ses pixels — presque toujours `.right` — et
    /// que ce qui part au service, ce sont les pixels : sans ça, la voiture
    /// arriverait couchée. Réduite parce que douze mégapixels n'apportent rien à
    /// un rendu de 1536 points de large et allongent l'envoi d'autant.
    private static func upright(_ photo: UIImage) -> CGImage? {
        let maxSide: CGFloat = 2048
        let scale = min(1, maxSide / max(photo.size.width, photo.size.height))
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }
}
