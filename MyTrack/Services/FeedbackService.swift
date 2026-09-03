//
//  FeedbackService.swift
//  MyTrack
//
//  Du message écrit dans les réglages au courrier électronique reçu.
//
//  Une seule voie, décrite dans `FeedbackConfiguration` : le relais, qui envoie
//  le courrier lui-même. Il n'y a pas de chemin de secours, et c'est voulu — un
//  second mécanisme d'envoi serait un second jeu de pannes à connaître, pour un
//  relais qui se déploie en deux minutes.
//
//  Ce que le service ajoute au message, il l'ajoute au vu et au su de celui qui
//  écrit : la version de l'app, celle d'iOS et le modèle de l'appareil sont
//  annoncés sous le champ de saisie, dans la feuille. Rien d'autre ne part —
//  pas un trajet, pas un véhicule, pas une ligne du profil.
//

import Foundation
import OSLog
import UIKit

/// Ce qui peut manquer en chemin. Sans texte : c'est la vue qui parle, elle
/// seule connaît la langue de l'app.
enum FeedbackError: Error {
    /// Pas de relais renseigné : il n'y a personne à qui envoyer le message.
    case notConfigured
    /// Le service n'a pas répondu, ou pas à temps.
    case serviceUnavailable
}

struct FeedbackService {
    /// Envoie le message, ou lève. Rien n'est mis en file : si l'envoi échoue,
    /// la feuille garde le texte et propose de recommencer — un message perdu
    /// en silence serait pire qu'un échec annoncé.
    func send(subject: String, message: String) async throws {
        let subject = "MyTrack — " + subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + Self.signature

        guard FeedbackConfiguration.isConfigured else {
            throw FeedbackError.notConfigured
        }
        try await viaRelay(subject: subject, body: body)
    }

    // MARK: - Le relais

    /// Le relais pose l'expéditeur et le destinataire sur l'envoi. L'app ne lui
    /// confie que ce qui a été écrit — voir `FeedbackConfiguration`.
    private func viaRelay(subject: String, body: String) async throws {
        guard let url = FeedbackConfiguration.endpointURL else {
            throw FeedbackError.notConfigured
        }
        struct Payload: Encodable {
            let subject: String
            let message: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            FeedbackConfiguration.sharedSecret, forHTTPHeaderField: "X-MyTrack-Secret"
        )
        request.httpBody = try? JSONEncoder().encode(Payload(subject: subject, message: body))

        try await Self.send(request)
    }

    // MARK: - Plomberie HTTP

    private static let timeout: TimeInterval = 30

    private static func send(_ request: URLRequest) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FeedbackError.serviceUnavailable
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw FeedbackError.serviceUnavailable
        }
        guard (200..<300).contains(status) else {
            // Le message du service vaut la peine d'être lu : c'est lui qui dit
            // si le domaine n'est pas vérifié ou la clé plus valable.
            AppLog.recording.error(
                "Commentaire refusé (\(status, privacy: .public)) : \(String(data: data, encoding: .utf8) ?? "", privacy: .public)"
            )
            throw FeedbackError.serviceUnavailable
        }
    }

    /// Les trois lignes ajoutées sous le message. Le modèle vient d'`uname` et
    /// non de `UIDevice.model`, qui ne sait dire que « iPhone » : « iPhone17,1 »
    /// est cryptique à lire mais c'est le seul qui désigne un appareil précis,
    /// et c'est ce qu'on cherche quand un écran se met de travers sur un seul
    /// modèle.
    private static var signature: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return """
            ---
            MyTrack \(version) (\(build))
            iOS \(UIDevice.current.systemVersion) — \(hardwareModel)
            """
    }

    private static var hardwareModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
