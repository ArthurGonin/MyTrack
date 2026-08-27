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
        let schema = Schema([
            Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        ])
        let container = Self.makeContainer(for: schema)

        modelContainer = container
        _appServices = State(initialValue: AppServices(modelContext: container.mainContext))
    }

    /// Opening the store can fail for two very different reasons: a schema
    /// change made during development (there is no migration plan yet), or a
    /// one-off problem — a full disk, a file left locked by a crash. Only the
    /// first is genuinely unrecoverable, so wiping the store is now the last
    /// resort rather than the first response: the open is retried once, the
    /// original error is logged, and an in-memory store takes over if even a
    /// fresh one can't be created — so a bad store can no longer crash launch,
    /// and a full disk no longer silently costs the user every trip they own.
    ///
    /// TODO: replace the reset with a real `SchemaMigrationPlan` before
    /// shipping — once the app is on the App Store, deleting the user's trips
    /// is never an acceptable answer to a schema change.
    private static func makeContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            AppLog.persistence.error("Opening the store failed: \(error.localizedDescription, privacy: .public)")
        }

        // A transient failure — the file briefly locked by a process that just
        // died — can clear on its own, and retrying costs nothing before wiping.
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            AppLog.persistence.notice("Store opened on the second attempt.")
            return container
        }

        AppLog.persistence.error("Store unreadable — deleting it and starting fresh.")
        let url = configuration.url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
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
