//
//  TripCostSnapshotService.swift
//  MyTrack
//
//  Fige sur les trajets ce que valait leur véhicule — consommation, prix de
//  l'énergie, énergie — pour ceux qui ne l'ont pas encore.
//
//  Les trajets enregistrés depuis reçoivent ces chiffres au moment où le
//  véhicule leur est attaché (`Trip.assignVehicle`). Restent ceux d'avant, qui
//  n'en ont aucun : sans ce rattrapage ils suivraient le véhicule pour toujours,
//  et corriger le prix du carburant réécrirait leur coût — exactement ce que le
//  fait de figer sert à empêcher.
//
//  Au lancement, et non pas au moment où le véhicule est modifié : les chiffres
//  qu'on grave sont alors ceux avec lesquels l'utilisateur a déjà vécu une
//  session entière. Corriger dans la foulée une consommation mal tapée reste
//  donc sans conséquence, là où figer à chaque modification aurait gravé la
//  faute de frappe sur tous les anciens trajets, sans moyen de revenir dessus.
//

import Foundation
import OSLog
import SwiftData

final class TripCostSnapshotService {
    /// Un trajet sans consommation figée dont le véhicule en a une reçoit les
    /// trois chiffres d'un coup — la consommation, le prix (même absent) et
    /// l'énergie — parce qu'ils ne valent qu'ensemble : garder le prix libre de
    /// bouger reviendrait à ne rien avoir figé du tout.
    ///
    /// Rien n'est écrit tant que le véhicule n'a pas de consommation : il n'y a
    /// alors aucun coût à préserver, et le trajet repassera ici au prochain
    /// lancement, une fois la fiche remplie.
    func freezeMissingFigures(in context: ModelContext) {
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.recordedConsumption == nil }
        )
        guard let trips = try? context.fetch(descriptor), !trips.isEmpty else { return }

        var didFreeze = false
        for trip in trips {
            guard let vehicle = trip.vehicle, let consumption = vehicle.consumption else { continue }
            trip.recordedConsumption = consumption
            trip.recordedEnergyPrice = vehicle.energyPrice
            trip.recordedEnergyType = vehicle.energyType
            didFreeze = true
        }

        guard didFreeze else { return }
        context.saveOrLog()
        AppLog.persistence.notice("Chiffres d'énergie figés sur les trajets qui n'en avaient pas.")
    }
}
