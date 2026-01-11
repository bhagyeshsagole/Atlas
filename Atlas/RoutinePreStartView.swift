//
//  RoutinePreStartView.swift
//  Atlas
//
//  What this file is:
//  - Pre-start screen that shows a routine summary and lets the user jump into a workout session.
//
//  Where it’s used:
//  - Pushed from `RoutineListView` when the user taps a routine to begin.
//
//  Called from:
//  - `RoutineListView` navigationDestination presents this; it then pushes `WorkoutSessionView` when Start is tapped.
//
//  Key concepts:
//  - Uses `@Environment(\\.dismiss)` to close the screen and `@State` to trigger navigation into a session.
//
//  Safe to change:
//  - UI copy, spacing, or card heights to adjust how the summary reads.
//
//  NOT safe to change:
//  - Navigation trigger `showSession`; removing it prevents starting a workout from this screen.
//
//  Common bugs / gotchas:
//  - Forgetting to keep `safeAreaInset` background opaque can make bottom buttons blend with content.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//
import SwiftUI

struct RoutinePreStartView: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @State private var showSession = false // When true, navigates to the live WorkoutSessionView.

    /// VISUAL TWEAK: Adjust the summary card height by changing `summaryCardMaxHeight`.
    private let summaryCardMaxHeight: CGFloat = 480
    /// VISUAL TWEAK: Adjust bottom button spacing via `bottomActionPadding`.
    private let bottomActionPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                GlassCard {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                            sectionHeader("Summary")
                            if routine.isCoachSuggested {
                                Text("Titan suggested this routine to shore up gaps and reach 10/10.")
                                    .appFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.secondary)
                            }
                            Text(spacedSummary(routine.summary))
                                .appFont(.body, weight: .regular)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(6)

                            Divider()

                            sectionHeader("Workouts")
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(routine.workouts) { workout in
                                    AtlasRowPill {
                                        Text(workout.name)
                                            .appFont(.body, weight: .semibold)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: summaryCardMaxHeight, alignment: .top)
                }
            }
            .padding(AppStyle.contentPaddingLarge)
            .padding(.bottom, bottomActionPadding + AppStyle.sectionSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .atlasBackground()
        .atlasBackgroundTheme(.workout)
        .safeAreaInset(edge: .bottom) {
            WorkoutActionBar(
                left: .init(title: "End Session", role: .destructive) {
                    Haptics.playLightTap()
                    dismiss()
                },
                right: .init(title: "Start Workout", role: nil) {
                    Haptics.playLightTap()
                    showSession = true
                }
            )
        }
        .navigationDestination(isPresented: $showSession) {
            WorkoutSessionView(routine: routine)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .appFont(.section, weight: .bold)
            .foregroundStyle(.primary)
    }

    private func spacedSummary(_ text: String) -> String {
        guard text.isEmpty == false else { return "Summary unavailable — regenerate later" }
        var spaced = text
        spaced = spaced.replacingOccurrences(of: "Focus:", with: "Focus:\n")
        spaced = spaced.replacingOccurrences(of: "Volume:", with: "\nVolume:")
        spaced = spaced.replacingOccurrences(of: "Rep ranges:", with: "Rep ranges:")
        spaced = spaced.replacingOccurrences(of: "Tip:", with: "\nTip:")
        return spaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    let sample = Routine(
        id: UUID(),
        name: "Push Day",
        createdAt: Date(),
        workouts: [
            RoutineWorkout(id: UUID(), name: "Bench Press", wtsText: "135 lb", repsText: "4x8"),
            RoutineWorkout(id: UUID(), name: "Overhead Press", wtsText: "95 lb", repsText: "3x10"),
            RoutineWorkout(id: UUID(), name: "Tricep Pushdown", wtsText: "45 lb", repsText: "3x12")
        ],
        summary: """
Focus: Chest + Shoulders
Volume: 6 exercises · moderate load
Rep ranges: mostly 8–12
Tip: rest 90–120s between sets
"""
    )
    return NavigationStack {
        RoutinePreStartView(routine: sample)
    }
}
