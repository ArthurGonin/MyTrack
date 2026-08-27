//
//  LocalizedNavigationTitle.swift
//  MyTrack
//
//  `navigationTitle("…")` ne se relit pas quand la langue change en cours de
//  route : la barre de navigation garde le titre résolu au premier affichage.
//  Le reste de l'écran suit pourtant la locale de l'environnement — d'où des
//  pages entièrement traduites sous un titre resté dans l'ancienne langue.
//
//  Le détour consiste à résoudre la chaîne ici, dans le corps de la vue, avec
//  la locale et le bundle courants : la barre reçoit alors une `String` dont la
//  *valeur* change, et c'est ce changement-là que SwiftUI voit passer.
//

import SwiftUI

extension View {
    func localizedNavigationTitle(_ key: String.LocalizationValue) -> some View {
        modifier(LocalizedNavigationTitle(key: key))
    }
}

private struct LocalizedNavigationTitle: ViewModifier {
    let key: String.LocalizationValue

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    func body(content: Content) -> some View {
        content.navigationTitle(String(localized: key, bundle: localizationBundle, locale: locale))
    }
}
