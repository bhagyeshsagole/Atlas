//
//  WorkoutView.swift
//  Atlas
//
//  What this file is:
//  - Simple screen that marks a workout as complete for today and returns home.
//
//  Where it’s used:
//  - Pushed from navigation flows when logging a quick “workout done” entry.
//
//  Called from:
//  - Can be navigated to from `ContentView` routes when a simple workout log is needed; writes to SwiftData for `HomeView` to read.
//
//  Key concepts:
//  - Uses `ModelContext` to insert a `Workout` model and `@Environment(\\.dismiss)` to pop the screen.
//
//  Safe to change:
//  - Copy, button styling, or haptic choice.
//
//  NOT safe to change:
//  - Removing date normalization (`startOfDay`) can create duplicate calendar entries for the same day.
//
//  Common bugs / gotchas:
//  - Forgetting to save the context after insert means the workout won’t persist.
//
//  DEV MAP:
//  - See: DEV_MAP.md → A) App Entry + Navigation
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

            // Finish button shares the unified pill sizing.
            AtlasPillButton("Finish Workout", systemImage: "checkmark.circle.fill") {
                finishWorkout()
            }

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
