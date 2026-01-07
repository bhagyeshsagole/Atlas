//
//  WorkoutSessionView.swift
//  Atlas
//
//  What this file is:
//  - Live workout logger that records sets, shows AI coaching, and ends sessions with a summary.
//
//  Where it’s used:
//  - Presented from `RoutinePreStartView` when a user starts a workout.
//
//  Called from:
//  - Launched via navigation from `RoutinePreStartView`; writes history through `HistoryStore` and presents `PostWorkoutSummaryView` on completion.
//
//  Key concepts:
//  - Combines local `@State` for UI drafts with SwiftData models via `HistoryStore` to persist sets.
//  - Uses sheets and safe area insets for bottom controls.
//
//  Safe to change:
//  - UI copy, spacing, or the look of set rows and coaching text.
//
//  NOT safe to change:
//  - Draft/session state wiring that writes through `HistoryStore`; altering it risks duplicate or missing sets.
//  - Dismissing summary sheet before `completedSessionId` is set; summary relies on the stored session.
//
//  Common bugs / gotchas:
//  - Forgetting to clear focus when switching exercises can leave the keyboard on the wrong field.
//  - Switching units without converting values will show inconsistent weight text.
//
//  DEV MAP:
//  - See: DEV_MAP.md → C) Workout Sessions / History (real performance logs)
//

import SwiftUI
import SwiftData

struct WorkoutSessionView: View {
    struct SessionExercise: Identifiable, Hashable {
        let id: UUID
        var name: String
        var orderIndex: Int
    }

    struct SetLogDraft {
        var weight: String = ""
        var reps: String = ""
        var tag: String = "S"
    }

    enum Field {
        case weight
        case reps
    }

    let routine: Routine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: String = "lb"

    @State private var exerciseIndex: Int = 0 // Tracks which exercise the user is editing.
    @State private var sessionExercises: [SessionExercise] // Ordered exercise list built from the routine.
    @State private var session: WorkoutSession? // SwiftData session persisted via HistoryStore.
    @State private var exerciseLogs: [UUID: ExerciseLog] = [:] // Cached SwiftData exercise rows per routine workout.
    @State private var loggedSets: [UUID: [SetLog]] = [:] // Sets already stored for each exercise ID.
    @State private var setDraft = SetLogDraft(tag: "W") // Current set entry fields.
    @State private var suggestions: [UUID: RoutineAIService.ExerciseSuggestion] = [:] // Cached AI coaching per exercise.
    @State private var lastSessionLines: [String] = [] // Formatted lines from the previous session for this exercise.
    @State private var lastSessionDate: Date?
    @State private var isLoadingCoaching = false // Indicates in-flight AI request.
    @State private var isAddingSet = false // Blocks duplicate set submissions.
    @State private var showAltPopup = false // Shows alternate tag popup when true.
    @State private var alternateButtonFrame: CGRect = .zero // Anchor frame for the alternate popup arrow.
    @State private var popupSize: CGSize = .zero // Helps position the popup relative to the button.
    @Environment(\.colorScheme) private var colorScheme
    @State private var completedSessionId: UUID?
    @State private var showSummary = false // Triggers the post-workout summary sheet.
    private let menuBackgroundOpacity: Double = 0.96
    private let menuBackgroundColorDark = Color.black
    private let menuBackgroundColorLight = Color.white
    @State private var newExerciseName: String = "" // For adding ad-hoc exercises mid-session.
    @FocusState private var focusedField: Field? // Keeps keyboard on weight or reps field.

    init(routine: Routine) {
        self.routine = routine
        _sessionExercises = State(initialValue: routine.workouts.enumerated().map { index, workout in
            SessionExercise(id: workout.id, name: workout.name, orderIndex: index)
        })
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                Text(currentExercise.name)
                    .appFont(.title, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, AppStyle.headerTopPadding)

                GlassCard {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                            coachingSection
                            Divider()
                            lastSessionSection
                            Divider()
                            thisSessionTargetsSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                setLogSection

                Spacer(minLength: 0)
            }
            .padding(AppStyle.contentPaddingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear {
                loadCoachingAndHistory()
            }
            .onChange(of: exerciseIndex) { _, _ in
                clearFocus()
                resetDraftForNewExercise()
                loadCoachingAndHistory()
            }

        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .tint(.primary)
        .safeAreaInset(edge: .bottom) {
            if !isEditingSetFields {
                bottomActions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(AppStyle.popupAnimation, value: isEditingSetFields)
            }
        }
        .overlay(alternatePopupOverlay)
        .onPreferenceChange(ViewFrameKey.self) { frame in
            alternateButtonFrame = frame
        }
        .sheet(isPresented: $showSummary) {
            if let sessionId = completedSessionId {
                PostWorkoutSummaryView(sessionID: sessionId) {
                    dismiss()
                }
            }
        }
    }

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            Text("Technique Tips")
                .appFont(.section, weight: .bold)
            Text(currentSuggestion?.techniqueTips ?? "Tips unavailable — continue logging.")
                .appFont(.body, weight: .regular)
                .foregroundStyle(.primary)
        }
    }

    private var lastSessionSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            Text("Last Session")
                .appFont(.section, weight: .bold)
            if lastSessionLines.isEmpty {
                Text("No previous sets logged.")
                    .appFont(.body, weight: .regular)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lastSessionLines, id: \.self) { line in
                        Text(line)
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var thisSessionTargetsSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            Text("This Session")
                .appFont(.section, weight: .bold)
            Text(currentSuggestion?.thisSessionPlan ?? "Dial in form and keep rest tight.")
                .appFont(.body, weight: .regular)
                .foregroundStyle(.primary)
        }
    }

    private var setLogSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Logged Sets")
                    .appFont(.section, weight: .bold)
                if loggedSetsForCurrent.isEmpty {
                    Text("No sets yet.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(loggedSetsForCurrent, id: \.id) { set in
                            AtlasRowPill {
                                HStack {
                                    Text(set.tag)
                                        .appFont(.body, weight: .semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule().fill(.white.opacity(0.1))
                                        )
                                    Text(setLine(set))
                                        .appFont(.body, weight: .regular)
                                    Spacer()
                                    Text(set.createdAt, style: .time)
                                        .appFont(.footnote, weight: .regular)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            AtlasRowPill {
                HStack(spacing: AppStyle.rowSpacing) {
                    Menu {
                        Button("W (Warm-up)") { setDraft.tag = "W" }
                        Button("S (Standard)") { setDraft.tag = "S" }
                        Button("DS (Drop Set)") { setDraft.tag = "DS" }
                    } label: {
                        Text(setDraft.tag)
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(.primary)
                            .frame(width: 54)
                    }

                    TextField(weightPlaceholder, text: $setDraft.weight)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                        .frame(width: 90)

                    TextField(repsPlaceholder, text: $setDraft.reps)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .reps)
                        .frame(width: 70)

                    Button {
                        addSet()
                    } label: {
                        Text("Add")
                            .appFont(.body, weight: .semibold)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAddingSet)
                }
            }
        }
    }

    private var bottomActions: some View {
        HStack(spacing: AppStyle.sectionSpacing) {
            AtlasPillButton("Alternate") {
                clearFocus()
                Haptics.playLightTap()
                showAltPopup = true
            }
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ViewFrameKey.self, value: proxy.frame(in: .global))
                }
            )
            AtlasPillButton(isLastExercise ? "End" : "Next") {
                clearFocus()
                Haptics.playLightTap()
                if isLastExercise {
                    endSession()
                } else {
                    goToNextExercise()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
        .padding(.bottom, AppStyle.startButtonBottomPadding)
        .background(
            Color(.systemBackground)
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var alternatePopupOverlay: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let horizontalPadding: CGFloat = AppStyle.screenHorizontalPadding
            let spacing: CGFloat = 8
            let popupWidth: CGFloat = 240

            let maxX = bounds.width - popupSize.width - horizontalPadding
            let clampedX = max(horizontalPadding, min(alternateButtonFrame.minX, maxX))

            let maxY = bounds.height - safeBottom - popupSize.height - spacing
            let desiredY = alternateButtonFrame.minY - popupSize.height - spacing
            let clampedY = max(safeTop + spacing, min(desiredY, maxY))

            ZStack(alignment: .topLeading) {
                if showAltPopup {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { showAltPopup = false }

                    alternatePopupContent
                        .frame(maxWidth: popupWidth, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                /// VISUAL TWEAK: Increase `menuBackgroundOpacity` if you can still see content behind the popup.
                                /// VISUAL TWEAK: Adjust `menuBackgroundColorDark/Light` to change the popup tone.
                                .fill((colorScheme == .dark ? menuBackgroundColorDark : menuBackgroundColorLight).opacity(menuBackgroundOpacity))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
                        .background(
                            GeometryReader { sizeProxy in
                                Color.clear
                                    .onAppear { popupSize = sizeProxy.size }
                                    .onChange(of: sizeProxy.size) { _, newValue in
                                        popupSize = newValue
                                    }
                            }
                        )
                        .offset(x: clampedX, y: clampedY)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .animation(AppStyle.popupAnimation, value: showAltPopup)
                }
            }
        }
    }

    private var alternatePopupContent: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick Exercise")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(.primary)
                ForEach(sessionExercises) { exercise in
                    if exercise.id != currentExercise.id {
                        Button {
                            exerciseIndex = exercise.orderIndex
                            showAltPopup = false
                        } label: {
                            HStack {
                                Text(exercise.name)
                                    .appFont(.body, weight: .regular)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if exercise.orderIndex == exerciseIndex {
                                    Image(systemName: "checkmark")
                                        .appFont(.caption, weight: .semibold)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().foregroundStyle(.primary.opacity(0.2))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add new workout")
                        .appFont(.body, weight: .semibold)
                    TextField("Name", text: $newExerciseName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addNewExercise()
                    }
                    .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)

            Button("Cancel") {
                showAltPopup = false
            }
            .appFont(.body, weight: .semibold)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    private var currentExercise: SessionExercise {
        sessionExercises[exerciseIndex]
    }

    private var isLastExercise: Bool {
        exerciseIndex >= sessionExercises.count - 1
    }

    private var currentSuggestion: RoutineAIService.ExerciseSuggestion? {
        suggestions[currentExercise.id]
    }

    private var isEditingSetFields: Bool {
        focusedField != nil
    }

    private var loggedSetsForCurrent: [SetLog] {
        loggedSets[currentExercise.id] ?? []
    }

    private var weightPlaceholder: String {
        guard let suggestion = currentSuggestion, let weightKg = suggestion.suggestedWeightKg else {
            return preferredUnit == .kg ? "kg" : "lb"
        }
        let weight = preferredUnit == .kg ? weightKg : weightKg * WorkoutSessionFormatter.kgToLb
        return String(format: "%.0f %@", weight, preferredUnit == .kg ? "kg" : "lb")
    }

    private var repsPlaceholder: String {
        currentSuggestion?.suggestedReps ?? "10-12"
    }

    private var preferredUnit: WorkoutUnits {
        WorkoutUnits(from: weightUnit) // AppStorage stores a string; convert to enum for conversions.
    }

    private func addSet() {
        guard !isAddingSet else { return }
        let trimmedReps = setDraft.reps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reps = Int(trimmedReps), reps > 0 else { return }

        let trimmedWeight = setDraft.weight.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedWeight = Double(trimmedWeight)
        let weightKg: Double?
        if let parsedWeight {
            // Convert to kg before storing so all history uses a single unit.
            weightKg = preferredUnit == .kg ? parsedWeight : parsedWeight / WorkoutSessionFormatter.kgToLb
        } else {
            weightKg = nil
        }

        isAddingSet = true
        Task {
            await MainActor.run {
                ensureSession()
            }

            guard let session else {
                isAddingSet = false
                return
            }

            let exerciseLog = ensureExerciseLog(for: currentExercise, in: session)
            let set = SetLog(
                tag: setDraft.tag,
                weightKg: weightKg,
                reps: reps,
                exercise: exerciseLog
            )
            exerciseLog.sets.append(set)
            do {
                try modelContext.save()
                await MainActor.run {
                    loggedSets[currentExercise.id, default: []].append(set)
                    setDraft = SetLogDraft(weight: "", reps: "", tag: setDraft.tag)
                    /// UX TWEAK: Dismiss keyboard after successfully adding a set by clearing focus.
                    focusedField = nil
                    /// UX TWEAK: Bottom action pills hide while typing (keyboard up) and reappear after Add/dismiss.
                    isAddingSet = false
                }
            } catch {
                #if DEBUG
                print("Save set error: \(error)")
                #endif
                await MainActor.run {
                    isAddingSet = false
                }
            }
        }
    }

    private func ensureSession() {
        guard session == nil else { return }
        let newSession = WorkoutSession(
            routineId: routine.id,
            routineTitle: routine.name,
            startedAt: Date(),
            endedAt: nil,
            isCompleted: false
        )
        modelContext.insert(newSession)
        session = newSession
    }

    private func ensureExerciseLog(for exercise: SessionExercise, in session: WorkoutSession) -> ExerciseLog {
        if let cached = exerciseLogs[exercise.id] {
            return cached
        }
        let log = ExerciseLog(name: exercise.name, orderIndex: exercise.orderIndex, session: session)
        modelContext.insert(log)
        exerciseLogs[exercise.id] = log
        session.exercises.append(log)
        return log
    }

    private func goToNextExercise() {
        guard exerciseIndex < sessionExercises.count - 1 else { return }
        /// VISUAL TWEAK: Default tag for a new exercise is set in `resetDraftForNewExercise()`.
        /// DEV NOTE: We do NOT reset tag after adding a set; tag persists until user changes it.
        resetDraftForNewExercise()
        exerciseIndex += 1
    }

    private func endSession() {
        guard let session else {
            dismiss()
            return
        }

        let hasAnySets = session.exercises.contains { !$0.sets.isEmpty }
        if !hasAnySets {
            modelContext.delete(session)
            do {
                if modelContext.hasChanges {
                    try modelContext.save()
                }
            } catch {
                #if DEBUG
                print("[HISTORY][ERROR] endSession delete save failed: \(error)")
                #endif
            }
            dismiss()
            return
        }

        session.isCompleted = true
        session.endedAt = Date()
        if let end = session.endedAt {
            session.durationSeconds = Int(end.timeIntervalSince(session.startedAt))
        }
        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
            completedSessionId = session.id
            showSummary = true
        } catch {
            #if DEBUG
            print("[HISTORY][ERROR] endSession save failed: \(error)")
            #endif
        }
    }

    private func loadCoachingAndHistory() {
        isLoadingCoaching = true
        let exerciseName = currentExercise.name
        let unit = preferredUnit
        let lastLog = WorkoutSessionHistory.latestExerciseLog(for: exerciseName, context: modelContext)
        lastSessionDate = lastLog?.session?.endedAt ?? lastLog?.session?.startedAt
        if let lastLog {
            lastSessionLines = WorkoutSessionFormatter.lastSessionLines(for: lastLog, preferred: unit)
        } else {
            lastSessionLines = []
        }

        let lastSessionText = lastSessionLines.joined(separator: "\n")

        Task {
            let suggestion = await RoutineAIService.generateExerciseCoaching(
                routineTitle: routine.name,
                routineId: routine.id,
                exerciseName: exerciseName,
                lastSessionSetsText: lastSessionText,
                lastSessionDate: lastSessionDate,
                preferredUnit: unit
            )
            await MainActor.run {
                suggestions[currentExercise.id] = suggestion
                isLoadingCoaching = false
            }
        }
    }

    private func addNewExercise() {
        let trimmed = newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextIndex = sessionExercises.count
        let newExercise = SessionExercise(id: UUID(), name: trimmed, orderIndex: nextIndex)
        sessionExercises.append(newExercise)
        newExerciseName = ""
        showAltPopup = false
        exerciseIndex = nextIndex
    }

    private func clearFocus() {
        focusedField = nil
    }

    private func resetDraftForNewExercise() {
        setDraft = SetLogDraft(weight: "", reps: "", tag: "W")
    }

    private func setLine(_ set: SetLog) -> String {
        WorkoutSessionFormatter.formatSetLine(set: set, preferred: preferredUnit)
    }
}

#Preview {
    NavigationStack {
        WorkoutSessionView(
            routine: Routine(
                id: UUID(),
                name: "Push",
                createdAt: Date(),
                workouts: [
                    RoutineWorkout(id: UUID(), name: "Bench Press", wtsText: "135 lb", repsText: "4x8"),
                    RoutineWorkout(id: UUID(), name: "OHP", wtsText: "95 lb", repsText: "3x10")
                ],
                summary: "Focus: Push\nVolume: 6 exercises"
            )
        )
        .modelContainer(for: [Workout.self, WorkoutSession.self, ExerciseLog.self, SetLog.self], inMemory: true)
    }
}

private struct ViewFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
