//
//  MotionActivityService.swift
//  MyTrack
//

import Foundation
import CoreMotion

final class MotionActivityService {
    private let activityManager = CMMotionActivityManager()

    func startMonitoring(onUpdate: @escaping (CMMotionActivity) -> Void) {
        activityManager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            onUpdate(activity)
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
    }
}
