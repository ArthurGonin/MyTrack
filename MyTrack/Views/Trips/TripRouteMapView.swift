//
//  TripRouteMapView.swift
//  MyTrack
//

import SwiftUI
import MapKit

struct TripRouteMapView: View {
    /// Un tronçon tracé d'un seul trait, avec son départ et son arrivée.
    ///
    /// Un trajet ordinaire n'en a qu'un. Un trajet fusionné en a un par
    /// composant : joindre leurs points bout à bout tirerait un trait de
    /// l'arrivée de l'un au départ du suivant, à travers une route que personne
    /// n'a prise — d'autant plus visible que les deux trajets sont éloignés.
    private struct Segment: Identifiable {
        /// Son rang dans le trajet, qui est aussi ce qui numérote ses drapeaux.
        let id: Int
        let routePoints: [RoutePoint]

        var coordinates: [CLLocationCoordinate2D] {
            routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    private let segments: [Segment]

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @State private var cameraPosition: MapCameraPosition

    /// Un trajet ordinaire : une seule trace, un seul départ, une seule arrivée.
    init(routePoints: [RoutePoint]) {
        self.init(routeSegments: [routePoints])
    }

    /// Un trajet fusionné : la trace de chaque composant, dans l'ordre où ils
    /// ont été roulés. Chacun garde son drapeau de départ et son drapeau
    /// d'arrivée, numérotés, pour qu'on voie de quoi le trajet est fait.
    init(routeSegments: [[RoutePoint]]) {
        segments = routeSegments
            // Un composant sans trace GPS ne se dessine pas, et ne doit pas non
            // plus décaler la numérotation de ceux qui en ont une.
            .filter { !$0.isEmpty }
            .enumerated()
            .map { Segment(id: $0.offset, routePoints: $0.element) }
        _cameraPosition = State(
            initialValue: Self.initialCameraPosition(for: routeSegments.flatMap { $0 })
        )
    }

    var body: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "Aucune trace GPS disponible",
                    systemImage: "map",
                    description: Text("Aucun point GPS n'a été enregistré pour ce trajet.")
                )
            } else {
                Map(position: $cameraPosition, interactionModes: .all) {
                    ForEach(segments) { segment in
                        let coordinates = segment.coordinates
                        if coordinates.count >= 2 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                        if let start = coordinates.first {
                            // Titres résolus ici plutôt que laissés en clé : ce que
                            // MapKit affiche est figé au premier rendu, comme le
                            // titre d'une barre de navigation.
                            Marker(
                                title(for: segment, isStart: true),
                                systemImage: "flag.circle.fill",
                                coordinate: start
                            )
                            .tint(.green)
                        }
                        if coordinates.count >= 2, let end = coordinates.last {
                            Marker(
                                title(for: segment, isStart: false),
                                systemImage: "flag.checkered.circle.fill",
                                coordinate: end
                            )
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    /// « Départ » sur un trajet ordinaire, « Départ 2 » sur le deuxième tronçon
    /// d'un trajet fusionné : le numéro n'apparaît que là où il distingue
    /// quelque chose.
    private func title(for segment: Segment, isStart: Bool) -> String {
        guard segments.count > 1 else {
            return isStart
                ? String(localized: "Départ", bundle: localizationBundle, locale: locale)
                : String(localized: "Arrivée", bundle: localizationBundle, locale: locale)
        }
        let rank = segment.id + 1
        return isStart
            ? String(localized: "Départ \(rank)", bundle: localizationBundle, locale: locale)
            : String(localized: "Arrivée \(rank)", bundle: localizationBundle, locale: locale)
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

#Preview("Trajet fusionné") {
    TripRouteMapView(routeSegments: [
        [
            RoutePoint(latitude: 48.8584, longitude: 2.2945, timestamp: .now.addingTimeInterval(-3600)),
            RoutePoint(latitude: 48.8625, longitude: 2.3010, timestamp: .now.addingTimeInterval(-3400)),
            RoutePoint(latitude: 48.8670, longitude: 2.3140, timestamp: .now.addingTimeInterval(-3200))
        ],
        [
            RoutePoint(latitude: 48.8760, longitude: 2.3400, timestamp: .now.addingTimeInterval(-1800)),
            RoutePoint(latitude: 48.8800, longitude: 2.3550, timestamp: .now.addingTimeInterval(-1600)),
            RoutePoint(latitude: 48.8830, longitude: 2.3700, timestamp: .now.addingTimeInterval(-1400))
        ]
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
