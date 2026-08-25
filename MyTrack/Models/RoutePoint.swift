//
//  RoutePoint.swift
//  MyTrack
//

import Foundation

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
}
