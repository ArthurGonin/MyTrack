//
//  MotionActivityService.swift
//  MyTrack
//

import Foundation
import OSLog
import CoreMotion

final class MotionActivityService {
    private let activityManager = CMMotionActivityManager()

    /// False on devices without a motion coprocessor — and in the Simulator,
    /// where automatic detection can't be exercised at all.
    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    /// Triggers the Motion & Fitness system prompt (if not already determined)
    /// and waits for the user's answer. CoreMotion has no dedicated "request
    /// authorization" API with a completion, so this queries a negligible
    /// time window instead — queryActivityStarting's handler reliably fires
    /// once authorization is resolved, granted or denied, unlike
    /// startActivityUpdates, which simply stays silent on denial.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let now = Date()
        await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: now, to: now, to: .main) { _, _ in
                continuation.resume()
            }
        }
    }

    func startMonitoring(onUpdate: @escaping (CMMotionActivity) -> Void) {
        guard isAvailable else {
            AppLog.recording.notice("Motion activity updates are unavailable on this device.")
            return
        }
        activityManager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            onUpdate(activity)
        }
    }

    func stopMonitoring() {
        activityManager.stopActivityUpdates()
    }
}
