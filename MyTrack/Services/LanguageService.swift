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

    /// Écrit seulement quand la langue change *vraiment*. Le garde n'est pas
    /// une optimisation : un `Picker` SwiftUI réaffecte sa sélection en se
    /// montant, avec la valeur qu'il vient d'y lire, et sans lui cette
    /// réaffectation à l'identique persistait la clé. L'app se retrouvait alors
    /// avec un choix explicite que personne n'avait fait — celui de l'écran de
    /// bienvenue, qui porte un menu de langues depuis
    /// `WelcomeLanguageStepView` — et cessait de suivre la langue de l'iPhone
    /// si elle changeait ensuite, ce que l'`init` ci-dessous cherche justement
    /// à préserver. Même famille de bug que dans `resetToSystemDefault()`.
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
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

    /// Le bundle de la langue choisie.
    ///
    /// `String(localized:)` ne choisit *pas* la traduction d'après la locale
    /// qu'on lui passe — celle-ci ne sert qu'à mettre en forme les valeurs
    /// interpolées. C'est le bundle qui décide, et par défaut il suit la langue
    /// du système. Sans ce détour, tout ce qui s'écrit hors SwiftUI — PDF,
    /// notifications — repartirait dans la langue de l'iPhone plutôt que dans
    /// celle de l'app. Les vues, elles, n'en ont pas besoin : `Text` résout ses
    /// clés à partir de la locale de l'environnement.
    /// Le calcul lui-même vit sur `AppLanguage`, l'écran de bienvenue ayant
    /// besoin du bundle des cinq autres langues en plus de celle-ci.
    var bundle: Bundle { language.bundle }

    init() {
        // Rien n'est écrit tant que l'utilisateur n'a pas choisi lui-même :
        // sans choix explicite, l'app suit la langue du système, y compris si
        // elle change plus tard.
        let storedLanguage = UserDefaults.standard.string(forKey: Self.selectedLanguageKey)
        language = storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
    }

    /// Remet la langue du système, pour qu'un compte supprimé retrouve une app
    /// d'avant tout premier lancement.
    ///
    /// L'effacement vient *après* l'affectation, et l'ordre inverse était un
    /// bug : le `didSet` de `language` réécrivait la clé dans la foulée, si bien
    /// qu'un compte supprimé se retrouvait avec un choix explicite — la langue
    /// du système à cet instant — et cessait de suivre celle de l'iPhone si elle
    /// changeait ensuite. C'est exactement ce que l'init cherche à éviter.
    func resetToSystemDefault() {
        language = .systemDefault
        UserDefaults.standard.removeObject(forKey: Self.selectedLanguageKey)
    }
}
