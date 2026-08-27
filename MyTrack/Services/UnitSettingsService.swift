//
//  UnitSettingsService.swift
//  MyTrack
//
//  Owns the display-unit preference. Stored in UserDefaults rather than
//  SwiftData — same choice as DrivingDetector's auto-detection flag — because
//  it's an app preference, not user data, and because adding a property to a
//  @Model would be a schema change the app has no migration plan for yet.
//

import Foundation
import Observation

@Observable
final class UnitSettingsService {
    private static let distanceUnitKey = "distanceUnit"

    var distanceUnit: DistanceUnit {
        didSet {
            UserDefaults.standard.set(distanceUnit.rawValue, forKey: Self.distanceUnitKey)
        }
    }

    init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.distanceUnitKey)
        distanceUnit = storedValue.flatMap(DistanceUnit.init(rawValue:)) ?? .systemDefault
    }
}
