//
//  LocalizationBundleEnvironment.swift
//  MyTrack
//
//  Le pendant de `\.locale` pour les chaînes que les vues construisent
//  elles-mêmes. `Text("…")` résout sa clé avec la locale de l'environnement,
//  mais `String(localized:)` non : il faut lui désigner le bundle de la langue,
//  sinon il retombe sur celle du système. Poser ce bundle dans
//  l'environnement, à côté de la locale, évite de le faire descendre à la main
//  d'écran en écran.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var localizationBundle: Bundle = .main
}
