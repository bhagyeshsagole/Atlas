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
    @StateObject private var historyStore: HistoryStore

    /// Builds the shared SwiftData container with all app models.
    /// Change impact: Adding or removing models here changes which data persists across launches.
    private static let sharedModelContainer: ModelContainer = {
        let container = AtlasPersistence.makeContainer()
        #if DEBUG
        let context = ModelContext(container)
        let count = (try? context.fetch(FetchDescriptor<WorkoutSession>()).count) ?? 0
        print("[BOOT] SwiftData persistent=\(!AtlasPersistence.isInMemory) sessionCount=\(count)")
        #endif
        return container
    }()

    init() {
        let context = ModelContext(Self.sharedModelContainer)
        _historyStore = StateObject(wrappedValue: HistoryStore(modelContext: context))
    }

    /// Builds the main scene and injects the shared model container.
    /// Change impact: Changing the root view or container wiring alters navigation and data availability across the app.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(routineStore)
                .environmentObject(historyStore)
                .task {
                    routineStore.load()
                }
        }
        .modelContainer(Self.sharedModelContainer)
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

    static var isInMemory: Bool = false

    static func makeContainer() -> ModelContainer {
        let schema = Schema(modelTypes)
        do {
            let config = ModelConfiguration("Atlas", schema: schema)
            let container = try ModelContainer(for: schema, configurations: config)
            #if DEBUG
            print("[BOOT] SwiftData container initialized (persistent default).")
            print("[BOOT] SwiftData schema includes: WorkoutSession, ExerciseLog, SetLog")
            #endif
            isInMemory = config.isStoredInMemoryOnly
            return container
        } catch {
            #if DEBUG
            print("[BOOT] SwiftData container failed: \(error). Falling back to in-memory.")
            #endif
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            isInMemory = true
            return (try? ModelContainer(for: schema, configurations: fallback))
        ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        }
    }
}
