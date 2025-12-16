//
//  AtlasApp.swift
//  Atlas
//
//  Created by Bhagyesh Sagole on 12/16/25.
//

import SwiftUI
import SwiftData

@main
struct AtlasApp: App {
    /// Builds the shared SwiftData container with all app models.
    /// Change impact: Adding or removing models here changes which data persists across launches.
    let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Workout.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Builds the main scene and injects the shared model container.
    /// Change impact: Changing the root view or container wiring alters navigation and data availability across the app.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
