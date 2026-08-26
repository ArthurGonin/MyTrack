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

    /// Whether the device reads as driving *right now*, from the activity
    /// already on record over the last `interval`.
    ///
    /// Needed because `startActivityUpdates` only ever delivers *changes* from
    /// the moment it's armed. A drive already under way when monitoring starts
    /// — the app woken from termination by a significant location change, the
    /// classic case this whole feature exists for — produces no sample at all
    /// until it ends, so the trip would be missed entirely.
    ///
    /// Only the most recent usable sample counts, not any automotive sample in
    /// the window: a drive that ended two minutes ago must not be resurrected
    /// as a trip that then has no change left to close it.
    func isAutomotiveNow(lookingBack interval: TimeInterval) async -> Bool {
        guard isAvailable, isAuthorized else { return false }
        let end = Date()
        let start = end.addingTimeInterval(-interval)
        return await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: start, to: end, to: .main) { activities, error in
                if let error {
                    AppLog.recording.error(
                        "Recent activity query failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let latest = activities?.last { $0.confidence != .low }
                continuation.resume(returning: latest?.automotive ?? false)
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
