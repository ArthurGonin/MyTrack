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

    /// Whether the user has already granted Motion & Fitness access.
    ///
    /// Worth checking before arming monitoring, because startActivityUpdates
    /// raises the system prompt as a side effect: without this, the app asks
    /// for motion access at whatever moment monitoring happens to start —
    /// a cold launch, for instance — instead of at the point in onboarding
    /// where the user asked for automatic tracking.
    var isAuthorized: Bool { CMMotionActivityManager.authorizationStatus() == .authorized }

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
