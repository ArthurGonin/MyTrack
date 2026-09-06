//
//  LegalContact.swift
//  MyTrack
//
//  L'adresse à laquelle on peut écrire au sujet des deux textes légaux.
//
//  Elle vit seule dans son fichier parce qu'elle est la seule chose de ces
//  documents qui ne s'écrit pas d'avance : le reste décrit ce que le code fait
//  déjà, celle-ci décrit une boîte aux lettres qui doit exister pour de bon.
//

import Foundation

enum LegalContact {
    /// L'adresse de contact, ou `nil` tant qu'il n'y en a pas.
    ///
    /// Le type reste optionnel bien qu'elle soit désormais renseignée : c'est
    /// lui qui fait disparaître proprement la dernière section des deux
    /// documents plutôt que d'y annoncer une adresse où personne ne lit —
    /// même principe que `appStoreID` dans `AccountSettingsView`. La vider
    /// reste donc une réponse valable, pas une panne.
    ///
    /// Elle est sur `kiwijuice.dev`, le domaine dont les DNS sont chez
    /// Cloudflare et qui porte déjà l'Email Routing du relais de commentaires
    /// (`Server/feedback/`). Une adresse écrite ici doit **recevoir pour de
    /// bon** : le RGPD comme la nLPD attendent un moyen de joindre le
    /// responsable, et une adresse qui rebondit est pire que l'absence de
    /// section — elle promet une porte qui n'existe pas. Vérifier dans
    /// *Email Routing → Routing Rules* qu'une règle achemine bien celle-ci
    /// vers une boîte réelle.
    static let email: String? = "contact@kiwijuice.dev"
}
