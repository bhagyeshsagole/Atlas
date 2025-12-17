//
//  ReviewRoutineView.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//

import SwiftUI

struct ReviewRoutineView: View {
    @EnvironmentObject private var routineStore: RoutineStore

    let routineName: String
    let onComplete: () -> Void

    @State private var editableWorkouts: [ParsedWorkout]

    init(routineName: String, workouts: [ParsedWorkout], onComplete: @escaping () -> Void) {
        self.routineName = routineName
        self.onComplete = onComplete
        _editableWorkouts = State(initialValue: workouts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                Text(routineName)
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.primary)

                if editableWorkouts.isEmpty {
                    Text("No workouts to review.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                        ForEach($editableWorkouts) { $workout in
                            AtlasRowPill {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(workout.name)
                                            .appFont(.title, weight: .semibold)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        AtlasHeaderIconButton(systemName: "xmark") {
                                            removeWorkout(workout.id)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 10) {
                                        TextField("wts", text: $workout.wtsText)
                                            .textFieldStyle(.roundedBorder)
                                            .tint(.primary)
                                        TextField("reps", text: $workout.repsText)
                                            .textFieldStyle(.roundedBorder)
                                            .tint(.primary)
                                    }
                                }
                            }
                        }
                    }
                }

                AtlasPillButton("Done") {
                    addRoutine()
                }
                .disabled(editableWorkouts.isEmpty)
            }
            .padding(AppStyle.contentPaddingLarge)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
    }

    private func removeWorkout(_ id: UUID) {
        editableWorkouts.removeAll { $0.id == id }
    }

    private func addRoutine() {
        let routine = Routine(
            id: UUID(),
            name: routineName,
            createdAt: Date(),
            workouts: editableWorkouts.map { workout in
                RoutineWorkout(
                    id: workout.id,
                    name: workout.name,
                    wtsText: workout.wtsText,
                    repsText: workout.repsText
                )
            }
        )
        routineStore.addRoutine(routine)
        #if DEBUG
        print("[AI] Saved routine '\(routine.name)' with \(routine.workouts.count) workouts. Total routines: \(routineStore.routines.count)")
        #endif
        onComplete()
    }
}
