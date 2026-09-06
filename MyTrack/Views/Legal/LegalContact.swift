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

    /// La page d'aide, celle qu'App Store Connect réclame dans la fiche sous le
    /// nom d'URL d'assistance.
    ///
    /// Obligatoire, et la guideline 1.5 demande que l'app *et* cette page
    /// offrent chacune un moyen simple de nous joindre : le formulaire de
    /// commentaire des réglages tient la première moitié, cette adresse la
    /// seconde. La page doit rester publique et sans compte à créer — Apple
    /// refuse une page d'accueil marketing ou un profil de réseau social.
    static let supportURL = URL(string: "https://mytrack.kiwijuice.dev/support")

    /// Le même texte que les réglages affichent hors ligne, publié à une
    /// adresse parce que la fiche de l'App Store en réclame une : l'écran
    /// embarqué ne dispense pas de cette exigence-là, qui est côté métadonnées
    /// (voir l'en-tête de `LegalDocument`). Les deux doivent donc dire la même
    /// chose — la page est produite depuis ce dépôt, catalogue de traductions
    /// compris, pour qu'elles ne puissent pas diverger.
    static let privacyPolicyURL = URL(string: "https://mytrack.kiwijuice.dev/privacy")
}
