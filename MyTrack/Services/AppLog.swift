//
//  AppLog.swift
//  MyTrack
//
//  Shared os.Logger categories. Failures that would otherwise be swallowed by
//  a bare `try?` are logged here, so a save that silently didn't happen can be
//  read in the Console instead of only surfacing as data reappearing at the
//  next launch.
//

import Foundation
import OSLog

nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MyTrack"

    /// SwiftData reads and writes.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    /// Driving detection, GPS tracking and trip confirmation notifications.
    static let recording = Logger(subsystem: subsystem, category: "recording")
    /// Report generation and the PDF files on disk.
    static let reports = Logger(subsystem: subsystem, category: "reports")
    /// StoreKit product loading, purchases, and entitlement state.
    static let purchases = Logger(subsystem: subsystem, category: "purchases")
}
