//
//  LanguageService.swift
//  MyTrack
//
//  Owns the language the app speaks. Stored in UserDefaults rather than
//  SwiftData — same choice as UnitSettingsService — because it's an app
//  preference, not user data.
//
//  L'app ne s'en remet pas à la langue du système : elle a son propre choix,
//  fait à l'onboarding, et impose sa `locale` à toute la hiérarchie SwiftUI.
//  C'est ce qui permet d'en changer sans redémarrer l'app, contrairement au
//  bricolage classique qui réécrit AppleLanguages.
//

import Foundation
import Observation

@Observable
final class LanguageService {
    private static let selectedLanguageKey = "selectedLanguage"

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.selectedLanguageKey)
        }
    }

    /// La langue choisie, posée sur la région du système : un Suisse qui lit
    /// l'app en allemand garde ses dates au format suisse. Seule la langue est
    /// remplacée, jamais le reste des conventions locales.
    var locale: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents.languageCode = Locale.LanguageCode(language.rawValue)
        return Locale(components: components)
    }

    init() {
        // Rien n'est écrit tant que l'utilisateur n'a pas choisi lui-même :
        // sans choix explicite, l'app suit la langue du système, y compris si
        // elle change plus tard.
        let storedLanguage = UserDefaults.standard.string(forKey: Self.selectedLanguageKey)
        language = storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
    }

    /// Remet la langue du système, pour qu'un compte supprimé retrouve une app
    /// d'avant tout premier lancement.
    func resetToSystemDefault() {
        UserDefaults.standard.removeObject(forKey: Self.selectedLanguageKey)
        language = .systemDefault
    }
}
