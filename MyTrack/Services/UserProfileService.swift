//
//  UserProfileService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class UserProfileService {
    /// The app has a single local profile — fetches it, creating one on first access.
    func currentProfile(in context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }
}
