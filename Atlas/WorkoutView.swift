//
//  WorkoutView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    /// Builds the Workout screen with a Finish control to persist today's workout.
    /// Change impact: Editing the button or layout here changes how the workout completes and feeds back to Home.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header text block.
            VStack(alignment: .leading, spacing: 6) {
                Text("Workout")
                    .font(.largeTitle.weight(.semibold))
                Text("Tap finish to log today and return.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Finish button: press feel comes from `PressableGlassButtonStyle`.
            Button {
                finishWorkout()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                    Text("Finish Workout")
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(PressableGlassButtonStyle())

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Saves today's workout, triggers haptic feedback, and returns to Home.
    /// Change impact: Adjusting date normalization or dismiss logic changes how the calendar updates after finishing.
    private func finishWorkout() {
        Haptics.playLightTap()
        let normalizedDate = calendar.startOfDay(for: Date())
        let workout = Workout(date: normalizedDate)
        modelContext.insert(workout)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    WorkoutView()
        .modelContainer(for: Workout.self, inMemory: true)
}
