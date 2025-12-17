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
        VStack(alignment: .leading, spacing: AppStyle.contentSpacingLarge) {
            // Header text block.
            VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
                /// VISUAL TWEAK: Change `AppStyle.titleBaseSize` or `AppStyle.fontBump` to resize the Workout title.
                /// VISUAL TWEAK: Adjust `AppStyle.subheaderSpacing` to tighten or loosen the title/subtitle gap.
                Text("Workout")
                    .appFont(.title, weight: .semibold)
                Text("Tap finish to log today and return.")
                    .appFont(.body, weight: .regular)
                    .foregroundStyle(.secondary)
            }

            // Finish button: press feel comes from `PressableGlassButtonStyle`.
            Button {
                finishWorkout()
            } label: {
                HStack(spacing: AppStyle.pillContentSpacing) {
                    Image(systemName: "checkmark.circle.fill")
                        .appFont(.pill, weight: .semibold)
                    Text("Finish Workout")
                        .appFont(.pill, weight: .semibold)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(PressableGlassButtonStyle())

            Spacer()
        }
        .padding(AppStyle.contentPaddingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Saves today's workout, triggers haptic feedback, and returns to Home.
    /// Change impact: Adjusting date normalization or dismiss logic changes how the calendar updates after finishing.
    private func finishWorkout() {
        /// VISUAL TWEAK: Change the haptic call here to adjust the Finish button feedback.
        /// VISUAL TWEAK: Swap `Haptics.playLightTap()` for another generator to change tap strength.
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
