//
//  ReportPeriodicity.swift
//  MyTrack
//

import Foundation

enum ReportPeriodicity: String, Codable, CaseIterable, Hashable {
    case none
    case monthly
    case quarterly
    case yearly
    case custom
}
