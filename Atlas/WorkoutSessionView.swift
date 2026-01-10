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
import Combine

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
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var routineStore: RoutineStore
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
    @State private var completedSessionId: UUID?
    @State private var showSummary = false // Triggers the post-workout summary sheet.
    @State private var newExerciseName: String = "" // For adding ad-hoc exercises mid-session.
    @State private var showNewWorkoutSheet = false
    @State private var isAddingNewWorkout = false // Blocks double add in sheet.
    @FocusState private var newWorkoutFieldFocused: Bool
    @FocusState private var focusedField: Field? // Keeps keyboard on weight or reps field.
    @State private var showTimerSheet = false
    @State private var timerMinutes: Int = 0
    @State private var timerSeconds: Int = 0
    @State private var timerRemaining: Int?
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var exerciseRefreshToken = UUID()
    @State private var derivedThisSessionPlan: String = "Dial in form and keep rest tight."
    @Environment(\.scenePhase) private var scenePhase
    @State private var dragOffset: CGFloat = 0
    @State private var didFireCompletionHaptic = false
    @State private var showEndConfirm = false
    @State private var showTipsSheet = false
    @State private var showPlanSheet = false
    @State private var pendingDeleteSetID: UUID?
    @State private var showConfirmDelete1 = false
    @State private var showConfirmDelete2 = false

    init(routine: Routine) {
        self.routine = routine
        _sessionExercises = State(initialValue: routine.workouts.enumerated().map { index, workout in
            SessionExercise(id: workout.id, name: workout.name, orderIndex: index)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            topPager
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, AppStyle.contentPaddingLarge)
            setLogSection
                .padding(.horizontal, AppStyle.contentPaddingLarge)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            reloadForCurrentExercise()
        }
        .onChange(of: exerciseIndex) { _, newIndex in
            clearFocus()
            resetDraftForNewExercise()
            reloadForCurrentExercise()
            #if DEBUG
            print("[SESSION][PAGER] index=\(newIndex) exercise=\(currentExercise.name)")
            #endif
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .tint(.primary)
        .safeAreaInset(edge: .bottom) {
            if !isEditingSetFields {
                bottomActions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(AppStyle.popupAnimation, value: isEditingSetFields)
            }
        }
        .sheet(isPresented: $showSummary) {
            if let sessionId = completedSessionId {
                PostWorkoutSummaryView(sessionID: sessionId) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showTimerSheet) {
            timerSheet
        }
        .sheet(isPresented: $showNewWorkoutSheet) {
            newWorkoutSheet
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if let remaining = timerRemaining {
                        Text(formattedTime(remaining))
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.primary)
                    }
                    Button {
                        Haptics.playLightTap()
                        showTimerSheet = true
                    } label: {
                        Image(systemName: "timer")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            guard let remaining = timerRemaining, remaining >= 0 else { return }
            if remaining > 1 {
                timerRemaining = remaining - 1
            } else {
                timerRemaining = nil
                if !didFireCompletionHaptic {
                    didFireCompletionHaptic = true
                    RestTimerHaptics.playCompletionPattern()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadForCurrentExercise()
            }
        }
        .overlay {
            if showConfirmDelete1 {
                GlassConfirmPopup(
                    title: "Remove this set?",
                    message: "This action cannot be undone.",
                    primaryTitle: "Continue",
                    secondaryTitle: "Cancel",
                    isDestructive: true,
                    isPresented: $showConfirmDelete1,
                    onPrimary: {
                        showConfirmDelete2 = true
                    },
                    onSecondary: {
                        pendingDeleteSetID = nil
                    }
                )
            }
            if showConfirmDelete2 {
                GlassConfirmPopup(
                    title: "Are you absolutely sure?",
                    message: "Remove this set permanently.",
                    primaryTitle: "Remove",
                    secondaryTitle: "Cancel",
                    isDestructive: true,
                    isPresented: $showConfirmDelete2,
                    onPrimary: {
                        if let id = pendingDeleteSetID, let set = loggedSetsForCurrent.first(where: { $0.id == id }) {
                            deleteSet(set)
                        }
                        pendingDeleteSetID = nil
                        showConfirmDelete1 = false
                    },
                    onSecondary: {
                        pendingDeleteSetID = nil
                        showConfirmDelete1 = false
                    }
                )
            }
            if showEndConfirm {
                GlassConfirmPopup(
                    title: "End workout?",
                    message: "This will finish the session and save your logged sets.",
                    primaryTitle: "End",
                    secondaryTitle: "Keep Going",
                    isDestructive: true,
                    isPresented: $showEndConfirm,
                    onPrimary: {
                        endSession()
                    },
                    onSecondary: { }
                )
            }
        }
    }

    private var topPager: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            pagerDots
            Text(currentExercise.name)
                .appFont(.title, weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            GlassCard {
                VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                    coachingSection
                    Divider()
                    lastSessionSection
                    Divider()
                    thisSessionTargetsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .offset(x: dragOffset)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 80
                        var newIndex = exerciseIndex
                        if value.translation.width < -threshold && exerciseIndex < sessionExercises.count - 1 {
                            newIndex += 1
                        } else if value.translation.width > threshold && exerciseIndex > 0 {
                            newIndex -= 1
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragOffset = 0
                            if newIndex != exerciseIndex {
                                exerciseIndex = newIndex
                            }
                        }
                    }
            )
        }
    }

    private var pagerDots: some View {
        HStack(spacing: 8) {
            ForEach(Array(sessionExercises.enumerated()), id: \.0) { index, _ in
                Group {
                    if index == exerciseIndex {
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 18, height: 6)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        exerciseIndex = index
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            HStack {
                Text("Technique Tips")
                    .appFont(.section, weight: .bold)
                Spacer()
                Button("More") {
                    showTipsSheet = true
                }
                .appFont(.footnote, weight: .semibold)
            }
            Text(currentSuggestion?.techniqueTips ?? "Tips unavailable — continue logging.")
                .appFont(.body, weight: .regular)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showTipsSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    Text("Technique Tips")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(currentSuggestion?.techniqueTips ?? "Tips unavailable — continue logging.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .padding(AppStyle.contentPaddingLarge)
                .background(Color.black.opacity(0.95).ignoresSafeArea())
            }
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lastSessionLines, id: \.self) { line in
                            Text(line)
                                .appFont(.body, weight: .regular)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var thisSessionTargetsSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            HStack {
                Text("This Session")
                    .appFont(.section, weight: .bold)
                Spacer()
                Button("More") {
                    showPlanSheet = true
                }
                .appFont(.footnote, weight: .semibold)
            }
            Text(thisSessionPlanText)
                .appFont(.body, weight: .regular)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showPlanSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    Text("This Session")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(thisSessionPlanText)
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .padding(AppStyle.contentPaddingLarge)
                .background(Color.black.opacity(0.95).ignoresSafeArea())
            }
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(loggedSetsForCurrent, id: \.id) { set in
                                AtlasRowPill {
                                    HStack(spacing: 12) {
                                        Text(set.tag)
                                            .appFont(.body, weight: .semibold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(.white.opacity(0.1))
                                            )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(weightText(for: set))
                                                .appFont(.body, weight: .semibold)
                                                .foregroundStyle(.primary)
                                            Text("× \(set.reps) reps")
                                                .appFont(.footnote, weight: .semibold)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    Capsule().fill(Color.white.opacity(0.08))
                                                )
                                        }
                                        Spacer()
                                        Button {
                                            pendingDeleteSetID = set.id
                                            showConfirmDelete1 = true
                                        } label: {
                                            Text("Remove")
                                                .appFont(.footnote, weight: .semibold)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule().fill(Color.white.opacity(0.08))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteSetID = set.id
                                        showConfirmDelete1 = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .scrollIndicators(.hidden)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { _ in }
                    )
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
        VStack(spacing: 12) {
            HStack(spacing: AppStyle.sectionSpacing) {
                AtlasPillButton("New Workout") {
                    clearFocus()
                    Haptics.playLightTap()
                    newWorkoutFieldFocused = true
                    showNewWorkoutSheet = true
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

                AtlasPillButton("End") {
                    clearFocus()
                    Haptics.playLightTap()
                    showEndConfirm = true
                }
                .frame(maxWidth: .infinity)
                    .tint(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
        .padding(.bottom, AppStyle.startButtonBottomPadding)
        .background(
            Color.black
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var currentExercise: SessionExercise {
        sessionExercises[exerciseIndex]
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
        let text = WeightFormatter.format(weightKg, unit: preferredUnit)
        return text
    }

    private var repsPlaceholder: String {
        currentSuggestion?.suggestedReps ?? "10-12"
    }

    private var preferredUnit: WorkoutUnits {
        WorkoutUnits(from: weightUnit) // AppStorage stores a string; convert to enum for conversions.
    }

    private var thisSessionPlanText: String {
        let plan = currentSuggestion?.thisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return plan.isEmpty ? derivedThisSessionPlan : plan
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
        ensureSession()

        guard let session else {
            isAddingSet = false
            return
        }

        let tag = SetTag(rawValue: setDraft.tag) ?? .S
        historyStore.addSet(
            session: session,
            exerciseName: currentExercise.name,
            orderIndex: currentExercise.orderIndex,
            tag: tag,
            weightKg: weightKg,
            reps: reps
        )

        if let exerciseLog = session.exercises.first(where: { $0.orderIndex == currentExercise.orderIndex }) {
            exerciseLogs[currentExercise.id] = exerciseLog
            loggedSets[currentExercise.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        }

        let nextWeight = trimmedWeight
        setDraft = SetLogDraft(weight: nextWeight, reps: "", tag: setDraft.tag)
        focusedField = nil
        isAddingSet = false
    }

    private func deleteSet(_ set: SetLog) {
        guard let session else { return }
        historyStore.deleteSet(set, from: session)
        if let exerciseLog = session.exercises.first(where: { $0.orderIndex == currentExercise.orderIndex }) {
            exerciseLogs[currentExercise.id] = exerciseLog
            loggedSets[currentExercise.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        }
    }

    private func ensureSession() {
        guard session == nil else { return }
        let exerciseNames = sessionExercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.name }
        let started = historyStore.startSession(
            routineId: routine.id,
            routineTitle: routine.name,
            exercises: exerciseNames,
            routineTemplateId: routine.id
        )
        session = started
        for exerciseLog in started.exercises {
            if let match = sessionExercises.first(where: { $0.orderIndex == exerciseLog.orderIndex }) {
                exerciseLogs[match.id] = exerciseLog
                loggedSets[match.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
            }
        }
    }

    private func goToNextExercise() {
        guard exerciseIndex < sessionExercises.count - 1 else { return }
        /// VISUAL TWEAK: Default tag for a new exercise is set in `resetDraftForNewExercise()`.
        /// DEV NOTE: We do NOT reset tag after adding a set; tag persists until user changes it.
        resetDraftForNewExercise()
        exerciseIndex += 1
    }

    private func goToPreviousExercise() {
        guard exerciseIndex > 0 else { return }
        resetDraftForNewExercise()
        exerciseIndex -= 1
    }

    private func endSession() {
        guard let session else {
            dismiss()
            return
        }

        let didStore = historyStore.endSession(session: session)
        if didStore {
            completedSessionId = session.id
            showSummary = true
            if routine.expiresOnCompletion {
                routineStore.deleteRoutine(id: routine.id)
            }
        } else {
            dismiss()
        }
    }

    private func reloadForCurrentExercise() {
        isLoadingCoaching = true
        let exerciseName = currentExercise.name
        let exerciseId = currentExercise.id
        let unit = preferredUnit
        let lastLog = WorkoutSessionHistory.latestExerciseLog(for: exerciseName, context: modelContext)
        lastSessionDate = lastLog?.session?.endedAt ?? lastLog?.session?.startedAt
        if let lastLog {
            lastSessionLines = WorkoutSessionFormatter.lastSessionLines(for: lastLog, preferred: unit)
            derivedThisSessionPlan = derivedPlan(from: lastLog, preferred: unit)
        } else {
            lastSessionLines = []
            derivedThisSessionPlan = "Dial in form and keep rest tight."
        }

        if let session, let exerciseLog = session.exercises.first(where: { $0.orderIndex == currentExercise.orderIndex }) {
            exerciseLogs[currentExercise.id] = exerciseLog
            loggedSets[currentExercise.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        }

        exerciseRefreshToken = UUID()
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
                guard exerciseId == currentExercise.id else { return }
                suggestions[currentExercise.id] = suggestion
                let plan = suggestion.thisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines)
                if !plan.isEmpty {
                    derivedThisSessionPlan = plan
                }
                exerciseRefreshToken = UUID()
                isLoadingCoaching = false
            }
        }
    }

    private func cleanExerciseName(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let apiKey = OpenAIConfig.apiKey, apiKey.isEmpty == false else {
            return fallbackCleanName(trimmed)
        }
        let cleaned = await RoutineAIService.cleanExerciseNameAsync(trimmed)
        let result = cleaned.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if result.isEmpty {
            return fallbackCleanName(trimmed)
        }
        #if DEBUG
        print("[AI][CLEAN] success input=\"\(trimmed)\" output=\"\(result)\"")
        #endif
        return result
    }

    private func fallbackCleanName(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let words = collapsed.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return words.joined(separator: " ")
    }

    private func derivedPlan(from lastLog: ExerciseLog, preferred: WorkoutUnits) -> String {
        let sets = lastLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        guard let top = sets.max(by: { lhs, rhs in
            let l = (lhs.weightKg ?? 0) * Double(lhs.reps)
            let r = (rhs.weightKg ?? 0) * Double(rhs.reps)
            return l < r
        }) else {
            return "Build on last session: add a clean set and keep rest ~90s."
        }
        let primary = WeightFormatter.format(top.weightKg, unit: preferred)
        let totalSets = sets.count
        let tagHint = (SetTag(rawValue: top.tag) == .DS) ? "ease volume, focus form" : "match or beat top set"
        return "\(primary) × \(top.reps) — \(tagHint); keep \(totalSets) sets sharp."
    }

    private var timerSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                Text("Rest Timer")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(.primary)

                HStack(spacing: 16) {
                    Picker("Minutes", selection: $timerMinutes) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text("\(minute) min").tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    Picker("Seconds", selection: $timerSeconds) {
                        ForEach(0..<60, id: \.self) { sec in
                            Text("\(sec) sec").tag(sec)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(maxHeight: 200)

                HStack(spacing: AppStyle.sectionSpacing) {
                    AtlasPillButton("Stop") {
                        timerRemaining = nil
                        didFireCompletionHaptic = false
                        Haptics.playLightTap()
                        showTimerSheet = false
                        #if DEBUG
                        print("[TIMER] stop tapped")
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                    .tint(.red)

                    AtlasPillButton("Start") {
                        let total = (timerMinutes * 60) + timerSeconds
                        timerRemaining = total
                        didFireCompletionHaptic = false
                        Haptics.playLightTap()
                        showTimerSheet = false
                        #if DEBUG
                        print("[TIMER] start total=\(total)")
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .background(Color.black.opacity(0.95).ignoresSafeArea())
        }
    }

    private var newWorkoutSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                Text("New Workout")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(.primary)

                TextField("Enter workout name", text: $newExerciseName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .padding(AppStyle.glassContentPadding)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(14)
                    .focused($newWorkoutFieldFocused)

                HStack(spacing: AppStyle.sectionSpacing) {
                    AtlasPillButton("Cancel") {
                        Haptics.playLightTap()
                        showNewWorkoutSheet = false
                    }
                    .frame(maxWidth: .infinity)

                    AtlasPillButton("Add") {
                        guard isAddingNewWorkout == false else { return }
                        isAddingNewWorkout = true
                        Haptics.playLightTap()
                        Task {
                            await addNewWorkoutFromSheet()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isAddingNewWorkout || newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .background(Color.black.opacity(0.95).ignoresSafeArea())
            .onAppear { newWorkoutFieldFocused = true }
        }
        .presentationDetents([.height(260)])
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func addNewWorkoutFromSheet() async {
        let trimmed = newExerciseName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            await MainActor.run {
                isAddingNewWorkout = false
            }
            return
        }
        let cleaned = await cleanExerciseName(trimmed)
        await MainActor.run {
            newExerciseName = ""
            isAddingNewWorkout = false
            showNewWorkoutSheet = false
        }
        await addNewExerciseNamed(cleaned)
    }

    @MainActor
    private func addNewExerciseNamed(_ name: String) async {
        let nextIndex = sessionExercises.count
        let newExercise = SessionExercise(id: UUID(), name: name, orderIndex: nextIndex)
        sessionExercises.append(newExercise)
        exerciseIndex = nextIndex
        if let session {
            if session.exercises.first(where: { $0.orderIndex == nextIndex }) == nil {
                let exerciseLog = ExerciseLog(name: name, orderIndex: nextIndex, session: session)
                session.exercises.append(exerciseLog)
                exerciseLogs[newExercise.id] = exerciseLog
                loggedSets[newExercise.id] = []
            }
        }
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

    private func weightText(for set: SetLog) -> String {
        WeightFormatter.format(set.weightKg, unit: preferredUnit)
    }
}

#Preview {
    let schema = Schema([Workout.self, WorkoutSession.self, ExerciseLog.self, SetLog.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)
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
        .environment(\.modelContext, context)
        .environmentObject(HistoryStore(modelContext: context))
    }
    .modelContainer(container)
}
