//
//  MyTrackApp.swift
//  MyTrack
//
//  Created by Arthur on 25.08.2026.
//

import SwiftUI
import OSLog
import SwiftData

@main
struct MyTrackApp: App {
    private let modelContainer: ModelContainer
    @State private var appServices: AppServices

    init() {
        // La liste des modèles vit dans `MyTrackSchemaV1`, et non ici : c'est
        // elle que le plan de migration nomme, et une seconde liste posée à
        // côté finirait par en différer d'un modèle — qui disparaîtrait alors
        // du magasin sans un mot.
        let schema = Schema(versionedSchema: MyTrackMigrationPlan.current)
        let container = Self.makeContainer(for: schema)

        modelContainer = container
        _appServices = State(initialValue: AppServices(modelContext: container.mainContext))
    }

    /// Ouvrir le magasin peut échouer pour deux raisons très différentes : un
    /// écart de schéma qu'aucune étape de `MyTrackMigrationPlan` ne sait
    /// franchir, ou un incident ponctuel — disque plein, fichier resté
    /// verrouillé par un plantage.
    ///
    /// Le premier cas relève désormais du plan de migration, qui traverse les
    /// versions au lieu de repartir de zéro. Ce qui suit n'est donc plus la
    /// réponse ordinaire à un changement de schéma : c'est le filet tendu sous
    /// ce que le plan n'a pas su faire.
    ///
    /// L'ordre y va du moindre dégât au pire : on réessaie une fois, on
    /// journalise l'erreur d'origine, on met le fichier de côté sans l'effacer,
    /// et un magasin en mémoire prend le relais si même un fichier neuf est
    /// impossible. De sorte qu'un magasin illisible ne peut plus fermer l'app
    /// au lancement, et qu'un disque plein ne coûte plus à l'utilisateur tous
    /// les trajets qu'il possède.
    private static func makeContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(
                for: schema, migrationPlan: MyTrackMigrationPlan.self, configurations: [configuration]
            )
        } catch {
            AppLog.persistence.error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
        }

        // A transient failure — the file briefly locked by a process that just
        // died — can clear on its own, and retrying costs nothing before wiping.
        if let container = try? ModelContainer(
            for: schema, migrationPlan: MyTrackMigrationPlan.self, configurations: [configuration]
        ) {
            AppLog.persistence.notice("Store opened on the second attempt.")
            return container
        }

        // Mis de côté, et non effacé. La différence ne se voit que le jour où
        // elle compte : les trajets d'une année entière tiennent dans ce
        // fichier, et rien ici ne sait dire si l'ouverture a échoué pour un
        // schéma que le plan de migration n'a pas su franchir — devenu l'anomalie
        // depuis qu'un plan existe — ou pour un disque plein, un fichier
        // verrouillé par un processus qui vient de mourir, une restauration à
        // moitié faite.
        // Effacer répondait la même chose aux deux, et la seconde réponse était
        // définitive. Renommé, le magasin reste récupérable : à la main, ou par
        // un futur plan de migration qui saura le relire.
        let url = configuration.url
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        AppLog.persistence.error("Store unreadable — moving it aside as .\(stamp, privacy: .public).bak")
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let archived = URL(fileURLWithPath: "\(file.path).\(stamp).bak")
            do {
                try FileManager.default.moveItem(at: file, to: archived)
            } catch {
                // Le déplacement lui-même peut échouer — disque plein, dossier en
                // lecture seule. On efface alors, faute de mieux : sans store
                // ouvrable, l'app ne démarre pas du tout.
                AppLog.persistence.error(
                    "Impossible de mettre le magasin de côté (\(error.localizedDescription, privacy: .public)) — effacement."
                )
                try? FileManager.default.removeItem(at: file)
            }
        }
        if let container = try? ModelContainer(
            for: schema, migrationPlan: MyTrackMigrationPlan.self, configurations: [configuration]
        ) {
            return container
        }

        // Nothing on disk works: run without persistence rather than crash, so
        // the user still gets a usable app and a diagnosable log.
        AppLog.persistence.fault("Falling back to an in-memory store — nothing recorded this session will be saved.")
        // An in-memory container can only fail if the schema itself is invalid,
        // which is a programming error rather than a runtime condition.
        return try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appServices.onboardingService.hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environment(appServices)
            // TEMP-PREDICATE-TEST
            .task {
                let context = modelContainer.mainContext
                if UserDefaults.standard.bool(forKey: "seedPredicateTest") {
                    let vehicle = Vehicle(name: "Essai prédicat")
                    context.insert(vehicle)
                    let statuses: [TripConfirmationStatus] =
                        [.pendingConfirmation, .pendingConfirmation, .confirmed, .deleted, .merged]
                    for (index, status) in statuses.enumerated() {
                        let trip = Trip(
                            startDate: .now.addingTimeInterval(Double(-3600 * (index + 1))),
                            source: .automatic, vehicle: vehicle
                        )
                        trip.endDate = .now
                        trip.confirmationStatus = status
                        context.insert(trip)
                    }
                    try? context.save()
                }

                // A — ce que fait le code aujourd'hui : toute la table, filtrée en Swift.
                let all = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
                let parSwift = all.filter { $0.confirmationStatus == .pendingConfirmation }.count

                // B — le prédicat, avec le cas capturé dans une variable locale.
                let pending = TripConfirmationStatus.pendingConfirmation
                let descriptor = FetchDescriptor<Trip>(
                    predicate: #Predicate { $0.confirmationStatus == pending }
                )
                let parCompte = (try? context.fetchCount(descriptor)) ?? -1
                let parFetch = ((try? context.fetch(descriptor)) ?? []).count

                AppLog.persistence.notice(
                    """
                    PREDICATE-TEST: total \(all.count, privacy: .public), \
                    swift \(parSwift, privacy: .public), \
                    fetchCount \(parCompte, privacy: .public), \
                    fetch \(parFetch, privacy: .public)
                    """
                )
            }
            // Tous les boutons de l'app en gélule. Posé ici plutôt que sur
            // chaque bouton : la forme se transmet par l'environnement, donc
            // un bouton ajouté plus tard la prend sans qu'on y pense — et
            // aucun ne peut rester rectangulaire par oubli.
            .buttonBorderShape(.capsule)
            // Toute la localisation de l'app passe par là : SwiftUI résout ses
            // chaînes et ses formats de date avec la locale de l'environnement,
            // donc changer de langue dans l'app se voit tout de suite, sans
            // redémarrage et sans toucher aux réglages du système.
            .environment(\.locale, appServices.languageService.locale)
            .environment(\.localizationBundle, appServices.languageService.bundle)
        }
        .modelContainer(modelContainer)
    }
}
