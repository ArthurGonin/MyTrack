//
//  ModelContext+Saving.swift
//  MyTrack
//

import Foundation
import OSLog
import SwiftData

extension ModelContext {
    /// Saves, logging the failure instead of discarding it the way `try?` does.
    ///
    /// A failed save is invisible otherwise: the change is already applied to
    /// the in-memory model, so the UI shows it as done and it only disappears
    /// at the next launch. Returns whether the change actually reached the
    /// store, so the few callers that must tell the user — deleting the
    /// account, editing the personal profile — can react instead of reporting
    /// a success that isn't one.
    @discardableResult
    func saveOrLog(_ operation: String = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            AppLog.persistence.error(
                "Save failed (\(operation, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
