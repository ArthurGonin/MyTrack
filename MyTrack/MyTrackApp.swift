//
//  MyTrackApp.swift
//  MyTrack
//
//  Created by Arthur on 25.08.2026.
//

import SwiftUI
import SwiftData

@main
struct MyTrackApp: App {
    private let modelContainer: ModelContainer
    @State private var appServices: AppServices

    init() {
        let schema = Schema([Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self])
        let configuration = ModelConfiguration(schema: schema)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Store from a schema predating an in-development model change: no migration
            // plan yet, so start fresh instead of crashing.
            let url = configuration.url
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            container = try! ModelContainer(for: schema, configurations: [configuration])
        }

        modelContainer = container
        _appServices = State(initialValue: AppServices(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appServices)
        }
        .modelContainer(modelContainer)
    }
}
