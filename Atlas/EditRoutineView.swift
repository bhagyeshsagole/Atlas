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
//  Called from:
//  - `RoutineListView` opens this view via navigationDestination when the user selects Edit.
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
    @State private var draftName: String
    @State private var editableWorkouts: [RoutineWorkoutDraft]
    @State private var newWorkoutName: String = ""

    let onSave: (Routine) -> Void

    init(routine: Routine, onSave: @escaping (Routine) -> Void) {
        _draft = State(initialValue: routine)
        _draftName = State(initialValue: routine.name)
        _editableWorkouts = State(initialValue: routine.workouts.map { RoutineWorkoutDraft(id: $0.id, name: $0.name, wtsText: $0.wtsText, repsText: $0.repsText) })
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Routine Name")
                            .appFont(.section, weight: .bold)
                        TextField("Name", text: $draftName)
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                    }
                }

                GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workouts")
                            .appFont(.section, weight: .bold)
                        ForEach($editableWorkouts) { $workout in
                            HStack {
                                TextField("Workout", text: $workout.name)
                                    .padding(AppStyle.settingsGroupPadding)
                                    .atlasGlassCard()
                                Button(role: .destructive) {
                                    deleteWorkout(id: workout.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                        }
                        TextField("New workout name", text: $newWorkoutName)
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                        Button {
                            addWorkout()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add Workout")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .atlasGlassCard()
                        }
                    }
                }
            }
            .padding(AppStyle.contentPaddingLarge)
        }
        .atlasBackground()
        .atlasBackgroundTheme(.workout)
        .navigationTitle("Edit Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(cleanDraft())
                    dismiss()
                }
            }
        }
    }

    private func deleteWorkout(id: UUID) {
        editableWorkouts.removeAll { $0.id == id }
    }

    private func addWorkout() {
        let trimmed = newWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let workout = RoutineWorkoutDraft(
            id: UUID(),
            name: trimmed,
            wtsText: "",
            repsText: ""
        )
        editableWorkouts.append(workout)
        newWorkoutName = ""
    }

    private func cleanDraft() -> Routine {
        var sanitized = draft
        let cleanedWorkouts = editableWorkouts.compactMap { workout -> RoutineWorkout? in
            let name = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else { return nil }
            return RoutineWorkout(id: workout.id, name: name, wtsText: workout.wtsText, repsText: workout.repsText)
        }
        sanitized.workouts = cleanedWorkouts
        sanitized = Routine(
            id: sanitized.id,
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sanitized.name : draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: sanitized.createdAt,
            workouts: sanitized.workouts,
            summary: sanitized.summary,
            source: sanitized.source,
            coachPlanId: sanitized.coachPlanId,
            expiresOnCompletion: sanitized.expiresOnCompletion,
            generatedForRange: sanitized.generatedForRange,
            coachName: sanitized.coachName,
            coachGroup: sanitized.coachGroup
        )
        return sanitized
    }
}

private struct RoutineWorkoutDraft: Identifiable {
    let id: UUID
    var name: String
    var wtsText: String
    var repsText: String
}
