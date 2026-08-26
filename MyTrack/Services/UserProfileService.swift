//
//  UserProfileService.swift
//  MyTrack
//

import Foundation
import SwiftData

final class UserProfileService {
    /// The app has a single local profile — fetches it, creating one on first access.
    func currentProfile(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        context.saveOrLog()
        return profile
    }
}
