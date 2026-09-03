//
//  Trip+Merge.swift
//  MyTrack
//
//  Rassembler plusieurs trajets en un seul, et les lui reprendre.
//
//  Le trajet fusionné est un trajet de plus, et non l'un des trajets choisis
//  promu au rang des autres : ses composants gardent chacun leur trace, leur
//  distance et leur coût, et se retrouvent tels quels sur son écran de détail.
//  C'est ce qui rend la fusion réversible — `separate` leur suffit à revenir
//  dans la liste, intacts.
//
//  Ici plutôt que dans un ViewModel : deux écrans s'en servent — la liste, qui
//  fusionne, et le détail, qui sépare — et cette logique-là parle des trajets
//  entre eux, pas de ce qu'un écran en montre. Même raison que `Trip+Cost`.
//

import Foundation
import SwiftData

extension Trip {
    /// Rassemble plusieurs trajets en un seul, inséré en base et rendu à
    /// l'appelant. Nil quand il n'y a rien à fusionner.
    ///
    /// Fusionner une fusion l'aplatit : les composants du trajet fusionné choisi
    /// passent au nouveau, qui le remplace. Un trajet fusionné rangé dans un
    /// autre donnerait un arbre dont l'écran de détail ne montrerait qu'un
    /// étage, et dont la carte perdrait les drapeaux des étages du dessous.
    ///
    /// Un trajet en cours d'enregistrement est refusé : sa distance grandit
    /// encore, et le trajet fusionné, lui, fige la sienne au moment de la
    /// fusion — il resterait faux pour toujours.
    @discardableResult
    static func merge(_ trips: [Trip], in context: ModelContext) -> Trip? {
        guard trips.count >= 2, trips.allSatisfy({ !$0.isActive }) else { return nil }

        // Relevé avant de rebrancher quoi que ce soit : `isMerged` répond par
        // les composants, et ils auront changé de trajet juste après.
        let emptiedMerges = trips.filter(\.isMerged)
        let components = trips
            .flatMap { $0.isMerged ? $0.orderedComponents : [$0] }
            .sorted { $0.startDate < $1.startDate }
        guard let first = components.first, let last = components.last else { return nil }

        let merged = Trip(startDate: first.startDate, source: .manual, vehicle: nil)
        context.insert(merged)
        // La fin du dernier trajet roulé, et non la plus tardive des dates de
        // fin : c'est la même chose ici, les composants étant tous terminés.
        merged.endDate = last.endDate
        merged.distanceMeters = components.reduce(0) { $0 + max(0, $1.distanceMeters) }
        // Les points sont recopiés plutôt que relus sur les composants : un
        // trajet fusionné est un trajet comme un autre, et tout ce qui lit
        // `routePoints` — le compte de points GPS, un futur export — doit y
        // trouver la course entière. La carte, elle, les reprend composant par
        // composant pour ne pas relier l'arrivée de l'un au départ du suivant
        // par un trait qui n'a jamais été roulé (voir `TripRouteMapView`).
        merged.routePoints = components.flatMap(\.routePoints)
        merged.startLatitude = first.startLatitude
        merged.startLongitude = first.startLongitude
        merged.endLatitude = last.endLatitude
        merged.endLongitude = last.endLongitude
        merged.vehicle = commonVehicle(of: components)

        for component in components {
            component.mergedInto = merged
            component.confirmationStatus = .merged
        }

        // Les fusions choisies ont donné leurs composants au nouveau trajet : il
        // ne reste d'elles qu'une coquille que plus rien n'affiche. Vidées avant
        // d'être effacées, sinon `.cascade` emporterait les composants qu'on
        // vient de leur reprendre.
        for emptied in emptiedMerges {
            emptied.mergedComponents = []
            context.delete(emptied)
        }

        context.saveOrLog()
        return merged
    }

    /// Défait la fusion : les composants retournent dans la liste tels qu'ils en
    /// étaient partis, et le trajet qui les rassemblait disparaît — il n'avait
    /// rien à lui que la somme de ce qu'ils portent.
    func separate(in context: ModelContext) {
        guard isMerged else { return }
        for component in orderedComponents {
            component.mergedInto = nil
            component.confirmationStatus = .confirmed
        }
        // Même précaution que plus haut : `.cascade` effacerait les composants
        // avec le trajet s'ils lui étaient encore rattachés.
        mergedComponents = []
        context.delete(self)
        context.saveOrLog()
    }

    /// Le véhicule de plusieurs trajets, seulement s'ils l'ont tous en commun.
    ///
    /// Rien sinon : un trajet fusionné qui porterait le nom d'une voiture pour
    /// la moitié de sa distance mentirait sur les deux, et son coût — la somme
    /// de ceux des composants — ne se rapporterait à aucune des deux fiches. La
    /// liste s'en sert de la même façon, pour savoir quel véhicule cocher dans
    /// la feuille qu'elle ouvre sur une sélection.
    static func commonVehicle(of trips: [Trip]) -> Vehicle? {
        guard let vehicle = trips.first?.vehicle else { return nil }
        return trips.allSatisfy { $0.vehicle === vehicle } ? vehicle : nil
    }
}
