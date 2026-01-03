//
//  ContentView.swift
//  Atlas
//
//  Overview: Root navigation shell coordinating home, routine creation, and settings flows.
//

import SwiftUI
import SwiftData

struct ContentView: View {
#if DEBUG
    @Environment(\.modelContext) private var modelContext
#endif
    /// DEV MAP: Root navigation stack and settings presentation live here.
    @State private var path: [Route] = []
    @State private var showSettings = false
    @AppStorage("appearanceMode") private var appearanceMode = "light"

    private enum Route: Hashable {
        case routines
        case createRoutine
        case reviewRoutine(RoutineDraft)
    }

    /// Builds the root navigation stack for Home and Workout flows.
    /// Change impact: Altering destinations or path management changes how users transition between screens.
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                startWorkout: { path.append(.routines) },
                openSettings: {
                    if !showSettings {
                        showSettings = true
                    }
                }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .routines:
                    RoutineListView {
                        path.append(.createRoutine)
                    }
                case .createRoutine:
                    CreateRoutineView { name, workouts in
                        path.append(.reviewRoutine(RoutineDraft(name: name, workouts: workouts)))
                    }
                case .reviewRoutine(let draft):
                    ReviewRoutineView(
                        routineName: draft.name,
                        workouts: draft.workouts
                    ) {
                        path = [.routines]
                    }
                }
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(onDismiss: { showSettings = false })
        }
        #if DEBUG
        .task {
            DevHistorySeeder.seedIfNeeded(modelContext: modelContext)
        }
        #endif
    }

    /// Resolves the app-wide color scheme based on stored appearance.
    /// Change impact: Tweaking mapping changes how the entire UI responds to appearance selection.
    private var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark": return .dark
        default: return .light
        }
    }
}

struct RoutineDraft: Hashable {
    let name: String
    let workouts: [ParsedWorkout]
}

#Preview {
    ContentView()
        .modelContainer(for: Workout.self, inMemory: true)
        .environmentObject(RoutineStore())
}
