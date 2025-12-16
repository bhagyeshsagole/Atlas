//
//  ContentView.swift
//  Atlas
//
//  Created by Bhagyesh Sagole on 12/16/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var path: [Route] = []
    @State private var showSettings = false
    @AppStorage("appearanceMode") private var appearanceMode = "light"

    private enum Route: Hashable {
        case workout
    }

    /// Builds the root navigation stack for Home and Workout flows.
    /// Change impact: Altering destinations or path management changes how users transition between screens.
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                startWorkout: { path.append(.workout) },
                openSettings: { showSettings = true }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .workout:
                    WorkoutView()
                }
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(onDismiss: { showSettings = false })
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

#Preview {
    ContentView()
        .modelContainer(for: Workout.self, inMemory: true)
}
