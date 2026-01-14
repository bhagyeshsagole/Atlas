//
//  ReviewRoutineView.swift
//  Atlas
//
//  What this file is:
//  - Review screen to edit AI-generated workouts before saving them as a routine.
//
//  Where it’s used:
//  - Pushed from `ContentView` after CreateRoutineView finishes parsing a routine.
//
//  Called from:
//  - Receives drafts from `CreateRoutineView` via navigation in `ContentView`, saves through `RoutineStore`, then returns via `onComplete`.
//
//  Key concepts:
//  - Uses `@State` arrays of `ParsedWorkout` so edits update the list live.
//  - Generates a summary via AI before saving to `RoutineStore`.
//
//  Safe to change:
//  - UI layout, button text, or validation messages.
//
//  NOT safe to change:
//  - Removing the guard against duplicate saves (`isSaving`); without it, multiple routines may save.
//  - Skipping the summary generation fallback; the UI expects a summary string.
//
//  Common bugs / gotchas:
//  - Forgetting to trim empty workouts leaves blank entries in saved routines.
//  - If you disable the alert binding, summary errors will silently fail.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//

import SwiftUI
import UniformTypeIdentifiers

struct ReviewRoutineView: View {
    @EnvironmentObject private var routineStore: RoutineStore

    let routineName: String
    let initialGroupId: String?
    let onComplete: () -> Void

    @State private var editableWorkouts: [ParsedWorkout] // Live list the user can edit before saving.
    @State private var isSaving = false // Prevents double-saves while AI summary completes.
    @State private var alertMessage: String?
    @State private var newWorkoutRawName: String = ""
    @State private var isAddingNewWorkout = false
    @FocusState private var newWorkoutFieldFocused: Bool
    @State private var draggingWorkoutId: UUID?
    @State private var lastHapticIndex: Int?

    init(routineName: String, workouts: [ParsedWorkout], initialGroupId: String? = nil, onComplete: @escaping () -> Void) {
        self.routineName = routineName
        self.initialGroupId = initialGroupId
        self.onComplete = onComplete
        _editableWorkouts = State(initialValue: workouts)
    }

    var body: some View {
        ZStack {
            Color.clear
                .atlasBackground()
                .atlasBackgroundTheme(.workout)
                .ignoresSafeArea()

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
                            ForEach(editableWorkouts) { workout in
                                AtlasRowPill {
                                    HStack(spacing: 12) {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 18, weight: .semibold))
                                            .padding(10)
                                            .background(Color.white.opacity(0.08), in: Circle())
                                        Text(workout.name)
                                            .appFont(.title, weight: .semibold)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        AtlasHeaderIconButton(systemName: "xmark") {
                                            removeWorkout(workout.id)
                                        }
                                        .disabled(isSaving)
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
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add new workout")
                            .appFont(.section, weight: .bold)
                            .foregroundStyle(.primary)
                        AtlasRowPill {
                            HStack(spacing: 12) {
                                TextField("Workout name", text: $newWorkoutRawName)
                                    .textInputAutocapitalization(.words)
                                    .disableAutocorrection(true)
                                    .tint(.primary)
                                    .focused($newWorkoutFieldFocused)
                                Button {
                                    addNewWorkout()
                                } label: {
                                    if isAddingNewWorkout {
                                        ProgressView()
                                            .tint(.primary)
                                    } else {
                                        Text("Add")
                                            .appFont(.body, weight: .semibold)
                                    }
                                }
                                .disabled(newWorkoutRawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingNewWorkout || isSaving)
                            }
                        }
                    }

                    AtlasPillButton("Done") {
                        addRoutine()
                    }
                    .disabled(editableWorkouts.isEmpty || isSaving)
                }
                .padding(AppStyle.contentPaddingLarge)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Routine")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .alert(alertMessage ?? "", isPresented: Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented { alertMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) { }
        }
    }

    private func removeWorkout(_ id: UUID) {
        editableWorkouts.removeAll { $0.id == id }
    }

    private func moveWorkout(_ id: UUID, offset: Int) {
        guard let idx = editableWorkouts.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = max(0, min(editableWorkouts.count - 1, idx + offset))
        guard newIndex != idx else { return }
        let item = editableWorkouts.remove(at: idx)
        editableWorkouts.insert(item, at: newIndex)
    }

    private func addNewWorkout() {
        let trimmed = newWorkoutRawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAddingNewWorkout = true
        Task {
            let cleaned = await RoutineAIService.cleanWorkoutName(trimmed)
            let name = cleaned.isEmpty ? trimmed : cleaned
            await MainActor.run {
                editableWorkouts.append(ParsedWorkout(name: name))
                newWorkoutRawName = ""
                newWorkoutFieldFocused = false
                isAddingNewWorkout = false
            }
        }
    }

    private func addRoutine() {
        guard !isSaving else { return }
        isSaving = true

        let routineId = UUID()
        let routineWorkouts = editableWorkouts.map { workout in
            RoutineWorkout(
                id: workout.id,
                name: workout.name,
                wtsText: workout.wtsText,
                repsText: workout.repsText
            )
        }

        Task {
            let summaryText: String
            do {
                summaryText = try await RoutineAIService.generateRoutineSummary(
                    routineTitle: routineName,
                    workouts: routineWorkouts
                )
            } catch let error as RoutineAIError {
                summaryText = "Summary unavailable. Try again."
                await MainActor.run {
                    alertMessage = summaryErrorMessage(for: error)
                }
            } catch {
                summaryText = "Summary unavailable. Try again."
                await MainActor.run {
                    alertMessage = "Could not generate summary: \(error.localizedDescription)"
                }
            }

            let routine = Routine(
                id: routineId,
                name: routineName,
                createdAt: Date(),
                workouts: routineWorkouts,
                summary: summaryText,
                coachGroup: initialGroupId
            )

            await MainActor.run {
                routineStore.addRoutine(routine)
                #if DEBUG
                print("[AI][SUMMARY] saved chars=\(summaryText.count)")
                print("[AI] Saved routine '\(routine.name)' with \(routine.workouts.count) workouts. Total routines: \(routineStore.routines.count)")
                #endif
                isSaving = false
                onComplete()
            }
        }
    }

    private func summaryErrorMessage(for error: RoutineAIError) -> String {
        switch error {
        case .serviceUnavailable:
            return "AI service not configured. Check Supabase URL/anon key."
        case .functionMissing:
            let base = SupabaseConfig.url?.absoluteString ?? "unknown Supabase URL"
            return "AI function missing (expected \(AIProxy.functionName) at \(base)/functions/v1/\(AIProxy.functionName)). Run tools/deploy_openai_proxy.sh then retry."
        case .notAuthenticated:
            return "Sign in required to use AI."
        case .httpStatus(let status, let body):
            let safeBody = body ?? ""
            let base = SupabaseConfig.url?.absoluteString ?? "unknown Supabase URL"
            if status == 403 {
                return "Sign in required to use AI. (HTTP 403) \(safeBody)"
            } else if status == 500 {
                return "Edge function deployed but crashing (HTTP 500) at \(base)/functions/v1/\(AIProxy.functionName). \(safeBody)"
            }
            return "AI error (HTTP \(status)) at \(base)/functions/v1/\(AIProxy.functionName). \(safeBody)"
        case .requestFailed(let underlying):
            return underlying
        case .decodeFailed:
            return "Could not parse the response."
        case .emptyResponse:
            return "Empty response."
        case .rateLimited:
            return "Rate limited."
        case .cancelled:
            return "Request cancelled."
        case .invalidURL:
            return "Invalid request URL."
        }
    }
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

        // Prevent invalid moves
        guard fromIndex != toIndex, fromIndex < items.count, toIndex < items.count else { return }

        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                let moved = items.remove(at: fromIndex)
                items.insert(moved, at: toIndex)

                #if DEBUG
                // Validate no duplicates after reorder
                let ids = Set(items.map { $0.id })
                if ids.count != items.count {
                    print("[REORDER ERROR] Duplicate IDs detected after reorder")
                }
                #endif
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
