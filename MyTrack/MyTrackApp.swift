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
        let container = try! ModelContainer(for: Trip.self, Vehicle.self, UserProfile.self)
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
