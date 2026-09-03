//
//  FeedbackConfiguration.swift
//  MyTrack
//
//  Où part le message que l'utilisateur écrit depuis les réglages.
//
//  Même partage des rôles que pour les photos de véhicule (voir
//  `StudioCutoutConfiguration`), et pour la même raison : une clé d'API posée
//  dans l'app se lit dans le bundle en deux minutes, et une clé Resend
//  extraite, c'est du courrier envoyé depuis votre domaine par n'importe qui.
//
//  **Le relais**, pour de vrai. Il détient la clé Resend, l'expéditeur vérifié
//  et la boîte qui reçoit ; l'app ne lui envoie qu'un titre et un texte. C'est
//  ce qui empêche d'en faire un relais ouvert : le destinataire n'est pas dans
//  la requête, donc personne ne peut s'en servir pour écrire ailleurs.
//
//  **La clé directe**, pour essayer. Elle appelle Resend depuis le téléphone,
//  sans rien déployer. Elle n'existe qu'en configuration Debug (`#if DEBUG`) :
//  une compilation Release n'en contient pas une ligne, donc elle ne peut pas
//  partir sur l'App Store même en l'oubliant remplie.
//

import Foundation

enum FeedbackConfiguration {
    /// L'adresse du relais, par exemple
    /// « https://mytrack-feedback.votre-compte.workers.dev ».
    ///
    /// TODO: à renseigner. Tant qu'elle est vide, la feuille s'ouvre et se
    /// remplit mais l'envoi répond « pas disponible » plutôt que d'avaler le
    /// message en silence.
    static let endpoint = ""

    /// Le même mot que celui posé côté relais. Il n'authentifie personne — il
    /// est dans l'app, donc extractible — il écarte les appels au hasard.
    static let sharedSecret = ""

    /// Vrai quand les deux sont renseignés. Un seul des deux ne sert à rien :
    /// le relais refuserait l'appel.
    static var isConfigured: Bool {
        !endpoint.isEmpty && !sharedSecret.isEmpty
    }

    static var endpointURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: endpoint)
    }

    #if DEBUG
    /// Une clé Resend (« re_… »), le temps d'un essai depuis Xcode. À vider
    /// avant de pousser sur un dépôt partagé — et de toute façon absente des
    /// compilations Release.
    static let debugResendKey = ""

    /// L'expéditeur, qui doit être sur un domaine vérifié chez Resend
    /// (« MyTrack <bonjour@votre-domaine.app> »), et la boîte qui reçoit.
    /// En production, ces deux-là vivent dans le relais et non ici.
    static let debugSender = ""
    static let debugRecipient = ""

    static var hasDebugKey: Bool {
        !debugResendKey.isEmpty && !debugSender.isEmpty && !debugRecipient.isEmpty
    }
    #endif
}
