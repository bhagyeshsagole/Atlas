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
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showSettings = false

    private enum Route: Hashable {
        case workout
    }

    /// Builds the root navigation stack for Home and Workout flows.
    /// Change impact: Altering destinations or path management changes how users transition between screens.
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                isDarkMode: $isDarkMode,
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
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(isDarkMode: $isDarkMode) {
                showSettings = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Workout.self, inMemory: true)
}
