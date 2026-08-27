//
//  OnboardingService.swift
//  MyTrack
//
//  Owns the onboarding state: whether it's been completed. Stored in
//  UserDefaults rather than SwiftData — same choice as UnitSettingsService —
//  because it's an app preference, not user data. La langue choisie à la
//  première page vit dans LanguageService : elle sert à toute l'app, pas
//  seulement à l'onboarding.
//

import Foundation
import Observation

@Observable
final class OnboardingService {
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.hasCompletedOnboardingKey)
        }
    }

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
    }

    /// Puts the app back to a first-launch state, so a deleted account is
    /// greeted by the onboarding again rather than a mostly-reset app.
    func resetToDefaults() {
        hasCompletedOnboarding = false
    }
}
