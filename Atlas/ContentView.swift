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

    private enum Route: Hashable {
        case workout
    }

    /// Builds the root navigation stack for Home and Workout flows.
    /// Change impact: Altering destinations or path management changes how users transition between screens.
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(isDarkMode: $isDarkMode) {
                path.append(.workout)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .workout:
                    WorkoutView()
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Workout.self, inMemory: true)
}
