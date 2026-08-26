//
//  LegalLinks.swift
//  MyTrack
//
//  Les deux URL légales que l'App Store exige sur un écran d'abonnement
//  (règle 3.1.2). Regroupées ici plutôt que dans la vue qui les affiche,
//  parce que la paywall et les réglages pointent vers les mêmes pages.
//

import Foundation

enum LegalLinks {
    // TODO: renseigner les deux URL réelles avant toute soumission à l'App
    // Store. Tant qu'elles valent nil, les liens de la paywall s'affichent en
    // texte grisé plutôt que d'ouvrir une page morte — mais Apple *refusera*
    // l'app tant qu'ils ne sont pas cliquables. Même principe que
    // `appStoreID` dans AccountSettingsView.
    //
    // Exemple : URL(string: "https://kiwijuice.app/mytrack/conditions")
    static let termsOfUse: URL? = nil
    static let privacyPolicy: URL? = nil
}
