//
//  TripRouteMapView.swift
//  MyTrack
//

import SwiftUI
import MapKit

struct TripRouteMapView: View {
    let routePoints: [RoutePoint]

    @State private var cameraPosition: MapCameraPosition
    @State private var isInteracting = false

    init(routePoints: [RoutePoint]) {
        self.routePoints = routePoints
        _cameraPosition = State(initialValue: Self.initialCameraPosition(for: routePoints))
    }

    private var coordinates: [CLLocationCoordinate2D] {
        routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Group {
            if routePoints.isEmpty {
                ContentUnavailableView(
                    "Aucune trace GPS disponible",
                    systemImage: "map",
                    description: Text("Aucun point GPS n'a été enregistré pour ce trajet.")
                )
            } else {
                map
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    // This map lives inside TripDetailView's scrollable List. A fully interactive
    // Map's own pan gesture competes with the List's scroll gesture and can make
    // the rest of the screen unreachable, so the map only claims pan/zoom once the
    // user explicitly taps it — until then, drags pass through and the page
    // scrolls normally.
    private var map: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $cameraPosition, interactionModes: isInteracting ? .all : []) {
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let start = coordinates.first {
                    Marker("Départ", systemImage: "flag.circle.fill", coordinate: start)
                        .tint(.green)
                }
                if coordinates.count >= 2, let end = coordinates.last {
                    Marker("Arrivée", systemImage: "flag.checkered.circle.fill", coordinate: end)
                        .tint(.red)
                }
            }
            .onTapGesture {
                if !isInteracting { isInteracting = true }
            }

            if isInteracting {
                Button {
                    isInteracting = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .font(.title2)
                }
                .padding(8)
            } else {
                Label("Toucher pour interagir", systemImage: "hand.tap")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(8)
            }
        }
    }

    /// Frames the whole route with padding, from a plain min/max lat/lon bounding
    /// box (MapKit has no built-in "region from points" API). A single point
    /// collapses the raw span to zero, which the minimum-span floor corrects for,
    /// so this one code path safely covers the 1-point case too.
    private static func initialCameraPosition(for points: [RoutePoint]) -> MapCameraPosition {
        guard !points.isEmpty else { return .automatic }

        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLon = longitudes.min()!
        let maxLon = longitudes.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let minimumSpanDegrees = 0.006
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, minimumSpanDegrees),
            longitudeDelta: max((maxLon - minLon) * 1.4, minimumSpanDegrees)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}

#Preview("Trajet") {
    TripRouteMapView(routePoints: [
        RoutePoint(latitude: 48.8584, longitude: 2.2945, timestamp: .now.addingTimeInterval(-600)),
        RoutePoint(latitude: 48.8600, longitude: 2.2960, timestamp: .now.addingTimeInterval(-540)),
        RoutePoint(latitude: 48.8625, longitude: 2.3010, timestamp: .now.addingTimeInterval(-480)),
        RoutePoint(latitude: 48.8650, longitude: 2.3070, timestamp: .now.addingTimeInterval(-420)),
        RoutePoint(latitude: 48.8670, longitude: 2.3140, timestamp: .now.addingTimeInterval(-360)),
        RoutePoint(latitude: 48.8690, longitude: 2.3220, timestamp: .now.addingTimeInterval(-300)),
        RoutePoint(latitude: 48.8710, longitude: 2.3280, timestamp: .now)
    ])
    .frame(height: 300)
}

#Preview("Point unique") {
    TripRouteMapView(routePoints: [
        RoutePoint(latitude: 48.8584, longitude: 2.2945, timestamp: .now)
    ])
    .frame(height: 300)
}

#Preview("Aucune trace") {
    TripRouteMapView(routePoints: [])
        .frame(height: 300)
}
