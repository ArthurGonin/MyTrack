//
//  OnboardingService.swift
//  MyTrack
//
//  Owns the onboarding state (whether it's been completed, and the language
//  chosen on its first page). Stored in UserDefaults rather than SwiftData —
//  same choice as UnitSettingsService — because it's an app preference, not
//  user data.
//

import Foundation
import Observation

@Observable
final class OnboardingService {
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private static let selectedLanguageKey = "selectedLanguage"

    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.hasCompletedOnboardingKey)
        }
    }

    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.selectedLanguageKey)
        }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        // Rien n'est écrit tant que l'utilisateur n'a pas choisi lui-même :
        // sans choix explicite, l'app suit la langue du système, y compris si
        // elle change plus tard — ce qui est le seul comportement sensé tant
        // qu'aucun réglage de langue n'existe en dehors de l'onboarding.
        let storedLanguage = UserDefaults.standard.string(forKey: Self.selectedLanguageKey)
        selectedLanguage = storedLanguage.flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
    }

    /// Puts the app back to a first-launch state, so a deleted account is
    /// greeted by the onboarding again rather than a mostly-reset app.
    func resetToDefaults() {
        hasCompletedOnboarding = false
        selectedLanguage = .systemDefault
    }
}
