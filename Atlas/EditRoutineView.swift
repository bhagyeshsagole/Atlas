//
//  EditRoutineView.swift
//  Atlas
//
//  What this file is:
//  - Simple form to edit a saved routine’s name and workouts.
//
//  Where it’s used:
//  - Presented from `RoutineListView` when the user chooses Edit on a routine.
//
//  Key concepts:
//  - Uses `@State` to hold an editable draft and `@Environment(\\.dismiss)` to close after saving.
//
//  Safe to change:
//  - Form layout, labels, or validation messaging.
//
//  NOT safe to change:
//  - The call to `onSave` with the edited draft; skipping it prevents persistence updates.
//
//  Common bugs / gotchas:
//  - Forgetting to trim empty workout names allows blank entries; guard against empty strings.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//
import SwiftUI

struct EditRoutineView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Routine // Local copy to edit before saving back.
    @State private var newWorkoutName: String = ""
    @State private var newWorkoutWts: String = ""
    @State private var newWorkoutReps: String = ""

    let onSave: (Routine) -> Void

    init(routine: Routine, onSave: @escaping (Routine) -> Void) {
        _draft = State(initialValue: routine)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $draft.name)
            }

            Section("Workouts") {
                ForEach($draft.workouts) { $workout in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.name)
                            .appFont(.body, weight: .semibold)
                        HStack {
                            TextField("Wts", text: $workout.wtsText)
                                .textFieldStyle(.roundedBorder)
                            TextField("Reps", text: $workout.repsText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .onDelete { indexSet in
                    draft.workouts.remove(atOffsets: indexSet)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Workout")
                        .appFont(.body, weight: .semibold)
                    TextField("Workout name", text: $newWorkoutName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Wts", text: $newWorkoutWts)
                            .textFieldStyle(.roundedBorder)
                        TextField("Reps", text: $newWorkoutReps)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Add") {
                        guard !newWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let workout = RoutineWorkout(
                            id: UUID(),
                            name: newWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines),
                            wtsText: newWorkoutWts.trimmingCharacters(in: .whitespacesAndNewlines),
                            repsText: newWorkoutReps.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        draft.workouts.append(workout)
                        newWorkoutName = ""
                        newWorkoutWts = ""
                        newWorkoutReps = ""
                    }
                }
            }
        }
        .navigationTitle("Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
            }
        }
    }
}
