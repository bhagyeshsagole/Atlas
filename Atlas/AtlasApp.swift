//
//  AtlasApp.swift
//  Atlas
//
//  Overview: App entry point wiring the SwiftData container and injecting shared stores.
//

import SwiftUI
import SwiftData

@main
struct AtlasApp: App {
    /// DEV MAP: App entry + shared model container wiring lives here.
    @StateObject private var routineStore = RoutineStore()
    /// Builds the shared SwiftData container with all app models.
    /// Change impact: Adding or removing models here changes which data persists across launches.
    let sharedModelContainer: ModelContainer = AtlasPersistence.makeContainer()

    /// Builds the main scene and injects the shared model container.
    /// Change impact: Changing the root view or container wiring alters navigation and data availability across the app.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(routineStore)
                .task {
                    routineStore.load()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

enum AtlasPersistence {
    /// DEV NOTE: Add/remove SwiftData @Model types in `modelTypes`.
    /// DEV NOTE: This intentionally avoids `url:` because it breaks compilation in current SwiftData API.
    static let modelTypes: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutSession.self,
        ExerciseLog.self,
        SetLog.self
    ]

    static func makeContainer() -> ModelContainer {
        let schema = Schema(modelTypes)
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            #if DEBUG
            print("[BOOT] SwiftData container failed: \(error). Falling back to in-memory.")
            #endif
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallback]))
        ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        }
    }
}
