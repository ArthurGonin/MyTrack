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

    var selectedLanguage: String {
        didSet {
            UserDefaults.standard.set(selectedLanguage, forKey: Self.selectedLanguageKey)
        }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        selectedLanguage = UserDefaults.standard.string(forKey: Self.selectedLanguageKey) ?? "fr"
    }

    /// Puts the app back to a first-launch state, so a deleted account is
    /// greeted by the onboarding again rather than a mostly-reset app.
    func resetToDefaults() {
        hasCompletedOnboarding = false
        selectedLanguage = "fr"
    }
}
