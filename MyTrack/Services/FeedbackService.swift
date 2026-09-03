//
//  FeedbackService.swift
//  MyTrack
//
//  Du message écrit dans les réglages au courrier électronique reçu.
//
//  Deux voies pour l'envoyer, décrites dans `FeedbackConfiguration` : le
//  relais, qui détient la clé Resend, et — en compilation Debug seulement — un
//  appel direct pour essayer sans rien déployer.
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
    /// Ni relais ni clé d'essai : il n'y a personne à qui envoyer le message.
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

        if FeedbackConfiguration.isConfigured {
            return try await viaRelay(subject: subject, body: body)
        }
        #if DEBUG
        if FeedbackConfiguration.hasDebugKey {
            return try await directlyToResend(subject: subject, body: body)
        }
        #endif
        throw FeedbackError.notConfigured
    }

    // MARK: - Les deux voies

    /// Le chemin de production : le relais pose la clé, l'expéditeur et le
    /// destinataire sur l'appel. L'app ne lui confie que ce qui a été écrit.
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

    #if DEBUG
    /// Le chemin d'essai : l'app parle à Resend elle-même, avec une clé posée à
    /// la main. Absent des compilations Release — voir `FeedbackConfiguration`.
    private func directlyToResend(subject: String, body: String) async throws {
        struct Payload: Encodable {
            let from: String
            let to: [String]
            let subject: String
            let text: String
        }

        var request = URLRequest(url: URL(string: "https://api.resend.com/emails")!)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeout
        request.setValue(
            "Bearer \(FeedbackConfiguration.debugResendKey)", forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            Payload(
                from: FeedbackConfiguration.debugSender,
                to: [FeedbackConfiguration.debugRecipient],
                subject: subject,
                text: body
            )
        )

        try await Self.send(request)
    }
    #endif

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
