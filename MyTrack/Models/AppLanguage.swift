//
//  AppLanguage.swift
//  MyTrack
//
//  Les langues que l'app propose. Seul l'écran de choix de l'onboarding s'en
//  sert pour l'instant : le reste de l'app n'est pas encore traduit, et cette
//  liste est ce sur quoi la traduction viendra se brancher.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portuguese = "pt"

    var id: String { rawValue }

    /// Chaque langue s'annonce dans sa propre langue, comme dans les Réglages
    /// d'iOS : quelqu'un qui cherche la sienne la reconnaît sans avoir à
    /// comprendre celle qui est affichée.
    var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .italian: "Italiano"
        case .portuguese: "Português"
        }
    }

    /// La première langue des préférences système que l'app sait parler.
    ///
    /// `preferredLanguages` est une liste ordonnée, pas une seule langue : un
    /// iPhone réglé en suédois avec l'espagnol en second doit ouvrir l'app en
    /// espagnol, pas en anglais. Les identifiants sont régionaux (« pt-BR »,
    /// « fr-CH ») et se réduisent donc à leur code de langue. L'anglais est le
    /// repli quand aucune ne correspond.
    static var systemDefault: AppLanguage {
        for identifier in Locale.preferredLanguages {
            guard let code = Locale.Language(identifier: identifier).languageCode?.identifier,
                  let language = AppLanguage(rawValue: code) else { continue }
            return language
        }
        return .english
    }
}
