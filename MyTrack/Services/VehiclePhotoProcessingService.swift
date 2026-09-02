//
//  VehiclePhotoProcessingService.swift
//  MyTrack
//
//  Le détourage d'une photo de véhicule, mené hors de l'écran qui l'a demandé.
//
//  Il vit ici et non dans la vue parce que l'appareil photo se ferme à
//  l'instant du déclenchement : le service met dix à trente secondes, et
//  personne ne doit rester à regarder une attente. Une tâche tenue par une vue
//  meurt avec elle — c'est exactement ce qu'il ne faut pas ici, où la vue est
//  faite pour disparaître aussitôt.
//
//  Ce qu'il publie, `state`, n'est pas un état d'avancement mais ce qu'il y a à
//  dire : une pastille en cours, une réussite qui s'efface d'elle-même, un
//  échec en trois mots. Les écrans s'y abonnent par `.vehiclePhotoToast()` et
//  n'en savent rien d'autre.
//
//  Une seule photo à la fois : une nouvelle prise annule celle qui traînait.
//  Reprendre une photo, c'est vouloir remplacer la précédente, pas les mettre
//  en file.
//

import Foundation
import Observation
import SwiftData
import UIKit

@Observable
final class VehiclePhotoProcessingService {
    /// Ce qui a manqué, dit dans les termes de quelqu'un qui attendait sa
    /// photo. Sans texte : c'est la pastille qui parle, elle seule connaît la
    /// langue de l'app.
    enum Failure: Equatable {
        /// Ni proxy ni clé d'essai : il n'y a personne à qui envoyer la photo.
        case notConfigured
        /// Le service n'a pas répondu, ou pas à temps.
        case unavailable
        /// Le plafond du jour est atteint.
        case quotaReached
        case processing

        init(_ error: Error) {
            switch error {
            case VehiclePhotoError.notConfigured: self = .notConfigured
            case VehiclePhotoError.serviceUnavailable: self = .unavailable
            case VehiclePhotoError.quotaReached: self = .quotaReached
            default: self = .processing
            }
        }
    }

    /// Ce qu'il y a à montrer, ou nil quand il n'y a rien à dire.
    enum State: Equatable {
        case processing
        case succeeded
        case failed(Failure)
    }

    private(set) var state: State?

    private let photoService: VehiclePhotoService
    private let modelContext: ModelContext
    /// Le détourage en cours, tenu pour pouvoir l'annuler quand une autre photo
    /// arrive.
    private var work: Task<Void, Never>?
    /// La minuterie qui efface la pastille. À part de `work` : elle court
    /// justement après que celui-ci a fini.
    private var expiry: Task<Void, Never>?

    init(photoService: VehiclePhotoService, modelContext: ModelContext) {
        self.photoService = photoService
        self.modelContext = modelContext
    }

    /// La photo confiée au service, et rangée sur le véhicule quand elle
    /// revient. Rend la main tout de suite : c'est le propre de cet écran de se
    /// fermer sans attendre.
    func process(_ photo: UIImage, for vehicle: Vehicle) {
        work?.cancel()
        expiry?.cancel()
        state = .processing

        work = Task {
            do {
                let data = try await photoService.processedPhoto(from: photo)
                try Task.checkCancellation()
                // Le véhicule a pu être supprimé pendant l'attente — l'écran
                // n'est plus là pour l'empêcher, maintenant que l'app reste
                // utilisable. Écrire sur une ligne qui n'existe plus n'aurait
                // aucun sens, et la pastille n'a personne à qui annoncer quoi.
                guard vehicle.modelContext != nil else {
                    state = nil
                    return
                }
                vehicle.photoData = data
                modelContext.saveOrLog()
                show(.succeeded, for: .seconds(2.5))
            } catch is CancellationError {
                // Remplacée par une autre prise : c'est la nouvelle qui parle
                // désormais, et elle a déjà posé sa pastille.
            } catch {
                show(.failed(Failure(error)), for: .seconds(4))
            }
        }
    }

    /// La pastille posée, puis retirée d'elle-même.
    ///
    /// Le délai vaut pour ce qui est fini — réussite comme échec. « En cours »
    /// n'en a pas : elle ne part que quand le travail part, sans quoi
    /// l'utilisateur croirait l'attente terminée alors qu'elle dure.
    private func show(_ state: State, for duration: Duration) {
        self.state = state
        expiry = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.state = nil
        }
    }
}
