//
//  FeedbackConfiguration.swift
//  MyTrack
//
//  Où part le message que l'utilisateur écrit depuis les réglages.
//
//  Un relais, comme pour les photos de véhicule (voir `StudioCutoutConfiguration`),
//  mais pour une raison de plus. Celle qu'on attend d'abord : rien qui ressemble
//  à une clé ne peut vivre dans l'app, où elle se lirait dans le bundle en deux
//  minutes. Ici il n'y en a même pas — c'est Cloudflare qui envoie le courrier,
//  par le lien `send_email` d'Email Routing, sans service de messagerie tiers ni
//  clé d'API d'aucune sorte.
//
//  L'autre raison est celle qui compte vraiment : l'app n'envoie jamais de
//  destinataire. Elle poste un titre et un texte, rien d'autre. L'expéditeur et
//  la boîte qui reçoit vivent dans les secrets du relais. C'est ce qui l'empêche
//  de servir à écrire ailleurs — même le secret partagé en main, on ne peut rien
//  faire de plus que nous écrire.
//
//  Le relais et sa mise en service sont dans `Server/feedback/`.
//
//  L'adresse ci-dessous n'est pas sur le même compte Cloudflare que celle du
//  détourage, et ce n'est pas un hasard : un Worker n'a le droit d'émettre que
//  depuis un domaine de son propre compte, donc celui-ci est déployé là où vit
//  `kiwijuice.dev`. Envoyer le relais sur l'autre compte le ferait répondre
//  « Envoi refusé : E_SENDER_DOMAIN_NOT_AVAILABLE ».
//

import Foundation

enum FeedbackConfiguration {
    /// L'adresse du relais, en service depuis le 3 septembre 2026.
    static let endpoint = "https://mytrack-feedback.8ghn2w9p7k.workers.dev"

    /// Le même mot que celui posé côté relais, et volontairement différent de
    /// celui du détourage : deux relais, deux mots, pour qu'un seul divulgué
    /// n'ouvre pas l'autre.
    ///
    /// Il n'authentifie personne — il est dans l'app, donc extractible — il
    /// écarte les appels au hasard.
    static let sharedSecret = "2b410d1f3073d65e782cd3a34ec1f8c53f6cd72c0dd76cfa"

    /// Vrai quand les deux sont renseignés. Un seul des deux ne sert à rien :
    /// le relais refuserait l'appel.
    static var isConfigured: Bool {
        !endpoint.isEmpty && !sharedSecret.isEmpty
    }

    static var endpointURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: endpoint)
    }
}
