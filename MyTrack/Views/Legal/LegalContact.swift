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
    /// TODO: renseigner avant toute soumission à l'App Store. Tant qu'elle vaut
    /// nil, les deux documents s'affichent sans leur dernière section plutôt
    /// que d'annoncer une adresse où personne ne lit — même principe que
    /// `appStoreID` dans `AccountSettingsView`. Un point d'attention pour la
    /// revue : le RGPD comme la nLPD attendent un moyen de contact, donc cette
    /// section manquante est une vraie lacune, pas une préférence.
    ///
    /// Exemple : "contact@kiwijuice.app"
    static let email: String? = nil
}
