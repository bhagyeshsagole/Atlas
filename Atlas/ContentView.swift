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
    @EnvironmentObject private var historyStore: HistoryStore
    /// DEV MAP: Root navigation stack and settings presentation live here.
    @State private var path: [Route] = []
    @State private var showSettings = false
    @State private var showIntro = true
    @AppStorage("appearanceMode") private var appearanceMode = "light"

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
