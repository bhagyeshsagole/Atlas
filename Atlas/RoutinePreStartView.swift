import SwiftUI

struct RoutinePreStartView: View {
    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @State private var showSession = false

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
                            Text(routine.summary.isEmpty ? "Summary unavailable — regenerate later" : routine.summary)
                                .appFont(.body, weight: .regular)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Divider()

                            sectionHeader("Workouts")
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(routine.workouts) { workout in
                                    AtlasRowPill {
                                        HStack(spacing: AppStyle.rowSpacing) {
                                            Text(workout.name)
                                                .appFont(.body, weight: .semibold)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(workoutMetaText(workout))
                                                .appFont(.footnote, weight: .regular)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
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
        .background(Color(.systemBackground))
        .tint(.primary)
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
        .navigationDestination(isPresented: $showSession) {
            WorkoutSessionView(routine: routine)
        }
    }

    private var bottomActions: some View {
        HStack(spacing: AppStyle.sectionSpacing) {
            AtlasPillButton("End Session") {
                Haptics.playLightTap()
                dismiss()
            }
            .frame(maxWidth: .infinity)
            AtlasPillButton("Start Workout") {
                Haptics.playLightTap()
                showSession = true
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
        .padding(.bottom, bottomActionPadding)
        .background(
            Color(.systemBackground)
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .appFont(.section, weight: .bold)
            .foregroundStyle(.primary)
    }

    /// VISUAL TWEAK: Hide/show workout right-side meta by editing `workoutMetaText(...)`.
    private func workoutMetaText(_ workout: RoutineWorkout) -> String {
        let repsDisplay = workout.repsText
            .replacingOccurrences(of: "x", with: "×")
            .replacingOccurrences(of: "X", with: "×")
        let weightDisplay = workout.wtsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = weightDisplay.isEmpty ? "—" : weightDisplay
        return repsDisplay.isEmpty ? right : "\(repsDisplay) · \(right)"
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
