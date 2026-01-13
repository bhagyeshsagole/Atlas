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
import UniformTypeIdentifiers

struct EditRoutineView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Routine // Local copy to edit before saving back.
    @State private var draftName: String
    @State private var editableWorkouts: [RoutineWorkoutDraft]
    @State private var newWorkoutName: String = ""
    @State private var draggingWorkoutId: UUID?
    @State private var lastHapticIndex: Int?

    let onSave: (Routine) -> Void

    init(routine: Routine, onSave: @escaping (Routine) -> Void) {
        _draft = State(initialValue: routine)
        _draftName = State(initialValue: routine.name)
        _editableWorkouts = State(initialValue: routine.workouts.map { RoutineWorkoutDraft(id: $0.id, name: $0.name, wtsText: $0.wtsText, repsText: $0.repsText) })
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.clear
                .atlasBackground()
                .atlasBackgroundTheme(.workout)
                .ignoresSafeArea()

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
                                HStack(spacing: 12) {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.system(size: 18, weight: .semibold))
                                        .padding(10)
                                        .background(Color.white.opacity(0.08), in: Circle())
                                        .foregroundStyle(.primary)

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
                                .contentShape(Rectangle())
                                .onDrag {
                                    draggingWorkoutId = workout.id
                                    lastHapticIndex = editableWorkouts.firstIndex(where: { $0.id == workout.id })
                                    return NSItemProvider(object: workout.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: RoutineReorderDelegate(
                                    item: workout,
                                    items: $editableWorkouts,
                                    draggingId: $draggingWorkoutId,
                                    lastHapticIndex: $lastHapticIndex
                                ))
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
        }
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

    private func moveWorkout(id: UUID, offset: Int) {
        guard let idx = editableWorkouts.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = max(0, min(editableWorkouts.count - 1, idx + offset))
        guard newIndex != idx else { return }
        let item = editableWorkouts.remove(at: idx)
        editableWorkouts.insert(item, at: newIndex)
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

private struct RoutineReorderDelegate<Item: Identifiable>: DropDelegate where Item.ID == UUID {
    let item: Item
    @Binding var items: [Item]
    @Binding var draggingId: UUID?
    @Binding var lastHapticIndex: Int?

    func dropEntered(info: DropInfo) {
        guard let draggingId, draggingId != item.id else { return }
        guard let fromIndex = items.firstIndex(where: { $0.id == draggingId }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.08)) {
                let moved = items.remove(at: fromIndex)
                items.insert(moved, at: toIndex)
            }
            if lastHapticIndex != toIndex {
                lastHapticIndex = toIndex
                Haptics.playLightTap()
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        lastHapticIndex = nil
        return true
    }
}
