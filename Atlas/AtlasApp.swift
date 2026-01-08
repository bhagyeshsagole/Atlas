//
//  AtlasApp.swift
//  Atlas
//
//  What this file is:
//  - App entry point that builds the data containers and injects shared stores into the UI.
//
//  Where it’s used:
//  - Runs at launch and wraps `ContentView` with environment objects for routines and history.
//  - Builds the SwiftData container that every screen depends on for persistence.
//
//  Called from:
//  - iOS app entry (main target) instantiates this `App` type; it then presents `ContentView`.
//
//  Key concepts:
//  - SwiftData `ModelContainer` is the on-device database; `ModelContext` is the handle we use to read/write it.
//  - `@StateObject` keeps shared stores alive for the whole app session instead of recreating them per view.
//
//  Safe to change:
//  - Logging lines or minor boot diagnostics; toggling debug prints.
//
//  NOT safe to change:
//  - The model list passed into the container or how the container is shared; changing this can break stored data.
//  - Environment injection of `RoutineStore` and `HistoryStore`, which routes data to the rest of the app.
//
//  Common bugs / gotchas:
//  - Removing a model from `modelTypes` can make SwiftData forget saved data for that type.
//  - Creating multiple `ModelContainer` instances will fragment persistence across screens.
//
//  DEV MAP:
//  - See: DEV_MAP.md → A) App Entry + Navigation
//
// FLOW SUMMARY:
// App launch → build SwiftData ModelContainer → create RoutineStore + HistoryStore → inject into ContentView → child screens read/write via shared context.
//

import SwiftUI
import SwiftData

@main
struct AtlasApp: App {
    /// DEV MAP: App entry + shared model container wiring lives here.
    @StateObject private var routineStore = RoutineStore()
    @StateObject private var historyStore: HistoryStore
    @StateObject private var authStore = AuthStore()

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
                .environmentObject(authStore)
                .task {
                    routineStore.load()
                    await authStore.restoreSessionIfNeeded()
                    authStore.startAuthListener()
                }
                .onOpenURL { url in
                    authStore.handleAuthRedirect(url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

enum AtlasPersistence {
    /// DEV NOTE: Add/remove SwiftData @Model types in `modelTypes`.
    static let modelTypes: [any PersistentModel.Type] = [
        Workout.self,
        WorkoutSession.self,
        ExerciseLog.self,
        SetLog.self
    ]

    static var isInMemory: Bool = false

    private static func persistentStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("AtlasData", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            print("[BOOT][ERROR] Failed to create store directory: \(error)")
            #endif
        }
        return directory.appendingPathComponent("Atlas.store")
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema(modelTypes)
        let storeURL = persistentStoreURL()
        do {
            let config = ModelConfiguration(
                "Atlas",
                schema: schema,
                url: storeURL
            )
            let container = try ModelContainer(for: schema, configurations: config)
            #if DEBUG
            print("[BOOT] SwiftData container initialized (persistent default).")
            print("[BOOT] SwiftData store url=\(storeURL.path)")
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
