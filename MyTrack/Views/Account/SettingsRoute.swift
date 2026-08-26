//
//  SettingsRoute.swift
//  MyTrack
//
//  Value-based navigation targets pushed onto AccountSettingsView's
//  NavigationStack — lets a notification tap deep-link straight to a given
//  report in the history, not just push the plain screens.
//

import Foundation

enum SettingsRoute: Hashable {
    case report
    case reportHistory(openingReportID: UUID?)
}
