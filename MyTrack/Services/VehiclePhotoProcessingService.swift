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
//  échec en trois mots. L'app s'y abonne en un seul endroit — un
//  `.vehiclePhotoToast()` posé à sa racine — et n'en sait rien d'autre.
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
    /// Le sursis demandé au système pour finir même si l'app passe derrière.
    private var grace: UIBackgroundTaskIdentifier = .invalid

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
        beginGrace()

        work = Task {
            defer { endGrace() }
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
                // Deux façons d'en arriver là, et ni l'une ni l'autre n'a rien
                // à dire ici : une autre prise a remplacé celle-ci, et sa
                // pastille est déjà posée ; ou le sursis a expiré, et c'est la
                // main du système qui a posé la sienne. Annoncer quoi que ce
                // soit maintenant écraserait l'une ou l'autre.
            } catch {
                show(.failed(Failure(error)), for: .seconds(4))
            }
        }
    }

    // MARK: - Le sursis

    /// Le temps que le système accorde à une app qui passe derrière avec du
    /// travail sur les bras.
    ///
    /// Sans lui, une app mise en arrière-plan est suspendue en quelques
    /// secondes, et une requête en vol se fige avec elle : jeter un œil à une
    /// notification pendant le détourage suffirait à perdre la photo — et
    /// l'appel à OpenAI aurait quand même été facturé. Le sursis dure une
    /// trentaine de secondes, ce qui couvre le coup d'œil, pas la pause café.
    ///
    /// Le rendre est obligatoire : le système ferme l'app d'un « was killed for
    /// not calling endBackgroundTask » si le délai passe sans qu'on ait rendu.
    /// D'où le `defer` sur la tâche, et le renoncement dans la main du système
    /// à l'expiration — une requête qui n'a pas abouti à temps n'aboutira pas.
    private func beginGrace() {
        endGrace()
        grace = UIApplication.shared.beginBackgroundTask(withName: "Détourage de la photo") {
            [weak self] in
            guard let self else { return }
            work?.cancel()
            // Dit avant de rendre la main, sans quoi la pastille tournerait
            // pour toujours : la tâche annulée, plus personne ne parle. Le
            // texte est celui de l'attente déçue, et c'est bien ce qui s'est
            // passé — la réponse n'est pas venue à temps.
            show(.failed(.unavailable), for: .seconds(4))
            endGrace()
        }
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grace)
        grace = .invalid
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
