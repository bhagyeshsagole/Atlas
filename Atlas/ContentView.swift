//
//  ContentView.swift
//  Atlas
//
//  What this file is:
//  - Root navigation shell that hosts the home screen, routine builder, and settings overlay.
//
//  Where it’s used:
//  - Entry for the NavigationStack that routes into routines, history, and settings.
//  - Sits under `AtlasApp` and wraps most screens the user sees.
//
//  Called from:
//  - Constructed in `AtlasApp` and shown in the main WindowGroup.
//
//  Key concepts:
//  - `NavigationStack` uses a `path` array to push/pop screens by value.
//  - `@AppStorage` keeps appearance choice in UserDefaults so it persists between launches.
//
//  Safe to change:
//  - Add/remove navigation routes, adjust intro timing, or tweak which view shows in a route.
//
//  NOT safe to change:
//  - The `Route` enum cases used in navigation destinations; removing cases breaks stored paths.
//  - How `historyStore.repairZeroTotalSessionsIfNeeded()` is called on appear (prevents stale data).
//
//  Common bugs / gotchas:
//  - Forgetting to pop/push using the `path` array can leave the stack in an inconsistent state.
//  - Accidentally keeping `showIntro` true will hide the app under the intro overlay.
//
//  DEV MAP:
//  - See: DEV_MAP.md → A) App Entry + Navigation
//
// FLOW SUMMARY:
// ContentView hosts NavigationStack → HomeView is root → taps push routines/history via Route → Settings shown as fullScreenCover over any route.
//

import SwiftUI
import SwiftData

struct ContentView: View {
#if DEBUG
    @Environment(\.modelContext) private var modelContext
#endif
    @EnvironmentObject private var historyStore: HistoryStore
    /// DEV MAP: Root navigation stack and settings presentation live here.
    @State private var path: [Route] = [] // Value-based navigation stack entries.
    @State private var showSettings = false // Drives the full-screen settings sheet.
    @State private var showIntro = true // Controls the launch overlay visibility.
    @AppStorage("appearanceMode") private var appearanceMode = "light" // Persists appearance choice in UserDefaults.

    private enum Route: Hashable {
        case routines
        case createRoutine
        case reviewRoutine(RoutineDraft)
        case history
    }

    /// Builds the root navigation stack for Home and Workout flows.
    /// Change impact: Altering destinations or path management changes how users transition between screens.
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HomeView(
                    startWorkout: { path.append(.routines) },
                    openSettings: {
                        if !showSettings {
                            showSettings = true
                        }
                    }
                )
                if showIntro {
                    IntroOverlay {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                            showIntro = false
                        }
                    }
                    .ignoresSafeArea()
                    .zIndex(1)
                }
            }
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
                case .history:
                    AllHistoryView()
                }
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(onDismiss: { showSettings = false })
        }
        .onAppear {
            historyStore.repairZeroTotalSessionsIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                    showIntro = false
                }
            }
        }
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

private struct IntroOverlay: View {
    let onFinish: () -> Void
    @State private var scale: CGFloat = 1.4

    var body: some View {
        ZStack(alignment: .center) {
            Color.black
            Text("Atlas")
                .appFont(.brand)
                .foregroundStyle(.white)
                .scaleEffect(scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                scale = 1.0
            }
        }
        .onTapGesture {
            onFinish()
        }
    }
}
