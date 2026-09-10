//
//  RoutePoint+Simplification.swift
//  MyTrack
//

import Foundation
import CoreLocation

extension RoutePoint {
    /// La même trace, avec beaucoup moins de points.
    ///
    /// Le GPS livre une mesure par seconde pendant tout le trajet : une heure
    /// de route fait trois mille six cents points, dont l'écrasante majorité ne
    /// dit rien de plus que ses voisins — sur une ligne droite d'autoroute,
    /// trois cents points décrivent ce que deux suffisent à dessiner. Ils
    /// coûtent pourtant à chaque écriture (`trip.routePoints` est un bloc
    /// unique), à chaque lecture, et à chaque rendu de la carte.
    ///
    /// L'algorithme est celui de Ramer-Douglas-Peucker : on garde les deux
    /// extrémités, on cherche le point qui s'écarte le plus du segment qui les
    /// joint, et on ne le garde que s'il s'en écarte de plus de `tolerance` —
    /// puis on recommence sur les deux moitiés. Ce qui disparaît est donc, par
    /// construction, ce dont l'absence ne déplace la trace de nulle part de
    /// plus que la tolérance.
    ///
    /// Elle ne s'applique qu'à la *trace*, jamais à la distance : celle-ci est
    /// mesurée sur les points bruts avant qu'on passe ici. Voir
    /// `TripRecorder.finalize`.
    static func simplified(_ points: [RoutePoint], tolerance: CLLocationDistance) -> [RoutePoint] {
        guard points.count > 2, tolerance > 0 else { return points }

        var isKept = [Bool](repeating: false, count: points.count)
        isKept[0] = true
        isKept[points.count - 1] = true

        // Une pile plutôt que la récursion, qui est la forme habituelle de cet
        // algorithme : elle descend d'un niveau par point dans le pire cas —
        // une trace en escalier, où chaque partage n'isole qu'un point — et
        // quelques milliers de niveaux débordent la pile d'appels.
        var pending = [(first: 0, last: points.count - 1)]
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }

            var farthest = first
            var largestGap: CLLocationDistance = 0
            for index in (first + 1)..<last {
                let gap = distance(from: points[index], toSegmentFrom: points[first], to: points[last])
                if gap > largestGap {
                    largestGap = gap
                    farthest = index
                }
            }

            // Sous la tolérance : tout ce qui sépare les deux extrémités tient
            // dans l'épaisseur du trait, et rien de cet intervalle n'est gardé.
            guard largestGap > tolerance else { continue }

            isKept[farthest] = true
            pending.append((first, farthest))
            pending.append((farthest, last))
        }

        return zip(points, isKept).compactMap { $1 ? $0 : nil }
    }

    /// La distance d'un point au segment joignant deux autres, en mètres.
    ///
    /// Le calcul est plan, sur une projection locale centrée en `start` : un
    /// segment de trace couvre au plus quelques kilomètres, sur lesquels la
    /// courbure de la Terre reste très en deçà de la tolérance, et la
    /// trigonométrie sphérique coûterait cher répétée des millions de fois.
    private static func distance(
        from point: RoutePoint,
        toSegmentFrom start: RoutePoint,
        to end: RoutePoint
    ) -> CLLocationDistance {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(start.latitude * .pi / 180)

        let endX = (end.longitude - start.longitude) * metersPerDegreeLongitude
        let endY = (end.latitude - start.latitude) * metersPerDegreeLatitude
        let pointX = (point.longitude - start.longitude) * metersPerDegreeLongitude
        let pointY = (point.latitude - start.latitude) * metersPerDegreeLatitude

        let segmentLengthSquared = endX * endX + endY * endY
        guard segmentLengthSquared > 0 else {
            // Les deux extrémités sont au même endroit : la trace fait une
            // boucle fermée sur cet intervalle, et c'est à ce point-là qu'on
            // mesure.
            return (pointX * pointX + pointY * pointY).squareRoot()
        }

        // Le pied de la perpendiculaire, ramené dans le segment. Sans ce
        // bornage on mesurerait la distance à la *droite* portant le segment :
        // un point situé au-delà d'une extrémité s'en trouverait tout proche
        // alors que la trace, elle, ne va pas jusque-là.
        let projection = max(0, min(1, (pointX * endX + pointY * endY) / segmentLengthSquared))
        let gapX = pointX - projection * endX
        let gapY = pointY - projection * endY
        return (gapX * gapX + gapY * gapY).squareRoot()
    }
}
