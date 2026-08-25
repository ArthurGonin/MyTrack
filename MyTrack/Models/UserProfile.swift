//
//  UserProfile.swift
//  MyTrack
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    var firstName: String
    var lastName: String
    var email: String
    var phoneNumber: String

    init(firstName: String = "", lastName: String = "", email: String = "", phoneNumber: String = "") {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
    }
}
