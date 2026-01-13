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
    var preloader: WorkoutSessionPreloader?
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
    @State private var showPickerSheet = false
    @State private var pickerWeightText: String = ""
    @State private var pickerReps: Int = 0
    @State private var pickerUnit: WorkoutUnits = .kg
    @State private var pickerTag: SetTag = .W
    @State private var setDraftWeightKg: Double?
    @State private var setDraftRepsInt: Int = 0
    @State private var frozenThisSessionPlan: String = ""
    @State private var frozenExerciseId: UUID?
    @State private var showTimerDoneOverlay = false
    @StateObject private var summaryLoader = PostWorkoutSummaryLoader()
    @State private var isEnding = false
    @State private var showSetHistorySheet = false
    @State private var showJumpSheet = false

    init(routine: Routine, preloader: WorkoutSessionPreloader? = nil) {
        self.routine = routine
        self.preloader = preloader
        _sessionExercises = State(initialValue: routine.workouts.enumerated().map { index, workout in
            SessionExercise(id: workout.id, name: workout.name, orderIndex: index)
        })
    }

    var body: some View {
        ZStack {
            sessionBackground
            sessionContent
        }
        .onAppear {
            reloadForCurrentExercise()
            if let remaining = timerRemaining, remaining > 0 {
                let endsAt = Date().addingTimeInterval(TimeInterval(remaining))
                RestTimerLiveActivityController.start(endsAt: endsAt, exerciseName: currentExercise.name)
            }
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
        .atlasBackgroundTheme(.workout)
        .tint(.primary)
        .safeAreaInset(edge: .bottom) { actionBarInset }
        .sheet(isPresented: $showSummary) { summarySheet }
        .sheet(isPresented: $showTimerSheet) { timerSheet }
        .sheet(isPresented: $showNewWorkoutSheet) { newWorkoutSheet }
        .sheet(isPresented: $showJumpSheet) { jumpSheet }
        .toolbar { sessionToolbar }
        .onReceive(timer) { _ in
            guard let remaining = timerRemaining, remaining >= 0 else { return }
            if remaining > 1 {
                timerRemaining = remaining - 1
            } else {
                timerRemaining = nil
                if !didFireCompletionHaptic {
                    didFireCompletionHaptic = true
                    RestTimerNotifier.cancelNotification()
                    RestTimerNotifier.playCompletion()
                    RestTimerLiveActivityController.end()
                    showTimerDoneOverlay = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if showTimerDoneOverlay {
                            showTimerDoneOverlay = false
                            RestTimerNotifier.stopCompletion()
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadForCurrentExercise()
            }
        }
        .overlay { overlays }
    }

    // MARK: - View composition

    @ViewBuilder private var sessionBackground: some View {
        Color.clear
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
            .ignoresSafeArea()
    }

    @ViewBuilder private var sessionContent: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            topPager
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, AppStyle.contentPaddingLarge)
            setLogSection
                .padding(.horizontal, AppStyle.contentPaddingLarge)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ToolbarContentBuilder private var sessionToolbar: some ToolbarContent {
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

    @ViewBuilder private var actionBarInset: some View {
        if !isEditingSetFields {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                HStack(spacing: 12) {
                    AtlasPillButton("Add Set") {
                        Haptics.playLightTap()
                        presentPicker()
                    }
                    .frame(maxWidth: .infinity)

                    AtlasPillButton("Add Exercise") {
                        Haptics.playLightTap()
                        showNewWorkoutSheet = true
                    }
                    .frame(maxWidth: .infinity)

                    AtlasPillButton("End") {
                        Haptics.playLightTap()
                        showEndConfirm = true
                    }
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                    .disabled(isEnding)
                }
                .padding(AppStyle.glassContentPadding)
            }
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.bottom, AppStyle.startButtonBottomPadding)
        }
    }

    @ViewBuilder private var overlays: some View {
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
        if showTimerDoneOverlay {
            timerDoneOverlay
                .transition(.opacity.combined(with: .scale))
        }
    }

    @ViewBuilder private var timerDoneOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    showTimerDoneOverlay = false
                    RestTimerNotifier.stopCompletion()
                }
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer Done")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text("Rest complete.")
                                .appFont(.body, weight: .medium)
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        AtlasPillButton("OK") {
                            showTimerDoneOverlay = false
                            RestTimerNotifier.stopCompletion()
                        }
                        .frame(maxWidth: 140)
                    }
                }
                .padding(AppStyle.glassContentPadding)
            }
            .padding(AppStyle.contentPaddingLarge)
        }
    }

    @ViewBuilder private var summarySheet: some View {
        if let sessionId = completedSessionId {
            PostWorkoutSummaryView(sessionID: sessionId, onDone: {
                dismiss()
            }, loader: summaryLoader)
        }
    }

    @ViewBuilder private var jumpSheet: some View {
        NavigationStack {
            List {
                ForEach(sessionExercises) { exercise in
                    Button {
                        exerciseIndex = exercise.orderIndex
                        showJumpSheet = false
                    } label: {
                        HStack {
                            Text(exercise.name)
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let sets = loggedSets[exercise.id], sets.isEmpty == false {
                                Circle()
                                    .fill(Color.green.opacity(0.8))
                                    .frame(width: 10, height: 10)
                            } else {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollIndicators(.hidden)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showJumpSheet = false }
                }
            }
            .atlasBackground()
        }
        .presentationDetents([.medium, .large])
    }

    private var topPager: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack {
                pagerDots
                Spacer()
                Button {
                    Haptics.playLightTap()
                    showJumpSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text("Exercises")
                    }
                    .appFont(.footnote, weight: .semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            Text(currentExercise.name)
                .appFont(.title, weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .center)
                .transaction { $0.animation = nil }
            if let muscleLine = muscleLineText, !muscleLine.isEmpty {
                Text(muscleLine)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }

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
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: dragOffset)
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
                        dragOffset = 0
                        if newIndex != exerciseIndex {
                            exerciseIndex = newIndex
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
                    exerciseIndex = index
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
                .atlasBackground()
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
                .atlasBackground()
            }
        }
    }

    private var setLogSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack {
                Text("Sets")
                    .appFont(.section, weight: .bold)
                Spacer()
                AtlasPillButton("Add Set") {
                    presentPicker()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: 120)
                .buttonStyle(.plain)
            }

            if let lastSet = loggedSetsForCurrent.last {
                Button {
                    showSetHistorySheet = true
                } label: {
                    HStack(spacing: 10) {
                        Text("Last Set")
                            .appFont(.caption, weight: .bold)
                            .foregroundStyle(.secondary)
                        if let tag = SetTag(rawValue: lastSet.tag) {
                            Text(tag.displayName)
                                .appFont(.caption, weight: .bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
                        Text("\(weightText(for: lastSet)) × \(lastSet.reps)")
                            .appFont(.body, weight: .semibold)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppStyle.glassContentPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .atlasGlassCard()
                }
                .buttonStyle(.plain)
            } else {
                Text("No sets yet. Add your first set to start tracking.")
                    .appFont(.body, weight: .regular)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPickerSheet) {
            SetEntrySheetView(
                weightText: $pickerWeightText,
                reps: $pickerReps,
                unit: $pickerUnit,
                tag: $pickerTag,
                onChange: { Haptics.playLightTap() },
                onLog: { weightKg, reps, tag in
                    setDraftWeightKg = weightKg
                    setDraftRepsInt = reps
                    setDraft.tag = tag.rawValue
                    addSet(weightKgOverride: weightKg, repsOverride: reps, tagOverride: tag, enteredUnitOverride: pickerUnit)
                },
                preferredUnit: preferredUnit,
                onUnitChange: { newUnit in
                    weightUnit = newUnit == .kg ? "kg" : "lb"
                }
            )
            .presentationDetents([.large])
            .atlasBackgroundTheme(.workout)
            .atlasBackground()
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showSetHistorySheet) {
            SetHistorySheet(
                sets: loggedSetsForCurrent.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) },
                weightText: weightText(for:),
                onDelete: { set in
                    Haptics.playLightTap()
                    deleteSet(set)
                }
            )
            .presentationDetents([.large])
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
                .disabled(isEnding)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            }
        }
        .padding(.horizontal, AppStyle.screenHorizontalPadding)
        .padding(.bottom, AppStyle.startButtonBottomPadding)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.85)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var currentExercise: SessionExercise {
        sessionExercises[exerciseIndex]
    }

    private var currentSuggestion: RoutineAIService.ExerciseSuggestion? {
        suggestions[currentExercise.id]
    }

    private var muscleLineText: String? {
        let muscles = ExerciseMuscleMap.detailedMuscles(for: currentExercise.name)
        let primaryText = muscles.primary.joined(separator: ", ")
        let secondaryText = muscles.secondary.joined(separator: ", ")
        let lines = [
            primaryText.isEmpty ? nil : "Primary: \(primaryText)",
            secondaryText.isEmpty ? nil : "Secondary: \(secondaryText)"
        ].compactMap { $0 }
        return lines.isEmpty ? nil : lines.joined(separator: " • ")
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
        let frozen = frozenThisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        if !frozen.isEmpty { return frozen }
        let derived = derivedThisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        if !derived.isEmpty { return derived }
        return "Warmup: light × 8–12 reps\nWorking: 3–4 sets × 6–10 reps."
    }

    private func addSet(weightKgOverride: Double? = nil, repsOverride: Int? = nil, tagOverride: SetTag? = nil, enteredUnitOverride: WorkoutUnits? = nil) {
        guard !isAddingSet else { return }
        let reps: Int
        if let repsOverride {
            reps = repsOverride
        } else {
            let trimmedReps = setDraft.reps.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Int(trimmedReps), parsed > 0 else { return }
            reps = parsed
        }

        let weightKg: Double?
        if let weightKgOverride {
            weightKg = weightKgOverride
        } else {
            let trimmedWeight = setDraft.weight.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedWeight = Double(trimmedWeight)
            if let parsedWeight {
                weightKg = preferredUnit == .kg ? parsedWeight : parsedWeight / WorkoutSessionFormatter.kgToLb
            } else {
                weightKg = nil
            }
        }

        isAddingSet = true
        ensureSession()

        guard let session else {
            isAddingSet = false
            return
        }

        let tag = tagOverride ?? SetTag(rawValue: setDraft.tag) ?? .S
        let enteredUnit = enteredUnitOverride ?? preferredUnit
        historyStore.addSet(
            session: session,
            exerciseName: currentExercise.name,
            orderIndex: currentExercise.orderIndex,
            tag: tag,
            weightKg: weightKg,
            reps: reps,
            enteredUnit: enteredUnit
        )

        if let exerciseLog = session.exercises.first(where: { $0.orderIndex == currentExercise.orderIndex }) {
            exerciseLogs[currentExercise.id] = exerciseLog
            loggedSets[currentExercise.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        }

        let nextWeightText: String
        if let weightKg {
            nextWeightText = String(format: "%.1f", weightKg)
        } else {
            nextWeightText = ""
        }
        setDraft = SetLogDraft(weight: nextWeightText, reps: "", tag: setDraft.tag)
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
        guard isEnding == false else { return }
        isEnding = true
        Task {
            if session == nil {
                ensureSession()
            }
            guard let session else {
                await MainActor.run {
                    isEnding = false
                    dismiss()
                }
                return
            }

            let didStore = historyStore.endSession(session: session)
            if didStore || session.totalSets > 0 {
                completedSessionId = session.id
                await summaryLoader.preload(sessionID: session.id, modelContext: modelContext, unitPreference: preferredUnit)
                await MainActor.run {
                    showSummary = true
                    if routine.expiresOnCompletion {
                        routineStore.deleteRoutine(id: routine.id)
                    }
                    isEnding = false
                }
            } else {
                await MainActor.run {
                    isEnding = false
                    dismiss()
                }
            }
        }
    }

    private func reloadForCurrentExercise() {
        isLoadingCoaching = true
        let exerciseName = currentExercise.name
        let exerciseId = currentExercise.id
        let unit = preferredUnit
        if let preloader, let cachedLines = preloader.lastLines[exerciseId] {
            lastSessionLines = cachedLines
            lastSessionDate = preloader.lastDates[exerciseId] ?? nil
            derivedThisSessionPlan = preloader.plans[exerciseId] ?? "Warmup: light × 8–12 reps\nWorking: 3–4 sets × 6–10 reps."
        } else {
            let lastLog = WorkoutSessionHistory.latestCompletedExerciseLog(
                for: exerciseName,
                excluding: session?.id,
                context: modelContext
            )
            lastSessionDate = lastLog?.session?.endedAt ?? lastLog?.session?.startedAt
            if let lastLog {
                lastSessionLines = WorkoutSessionFormatter.lastSessionLines(for: lastLog, preferred: unit)
                derivedThisSessionPlan = WorkoutSessionHistory.guidanceRange(from: lastLog, displayUnit: unit)
            } else {
                lastSessionLines = []
                derivedThisSessionPlan = "Warmup: light × 8–12 reps\nWorking: 3–4 sets × 6–10 reps."
            }
        }
        frozenThisSessionPlan = derivedThisSessionPlan
        frozenExerciseId = exerciseId
        #if DEBUG
        let preview = frozenThisSessionPlan.prefix(80)
        print("[SESSION][PLAN] freeze exerciseId=\(exerciseId) plan=\"\(preview)\"")
        #endif

        if let session, let exerciseLog = session.exercises.first(where: { $0.orderIndex == currentExercise.orderIndex }) {
            exerciseLogs[currentExercise.id] = exerciseLog
            loggedSets[currentExercise.id] = exerciseLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        }

        exerciseRefreshToken = UUID()
        let lastSessionText = lastSessionLines.joined(separator: "\n")

        if let cachedSuggestion = preloader?.suggestions[exerciseId] {
            suggestions[currentExercise.id] = cachedSuggestion
            isLoadingCoaching = false
            #if DEBUG
            print("[SESSION][PLAN] using cached suggestion exerciseId=\(exerciseId)")
            #endif
        } else {
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
                    #if DEBUG
                    let planPreview = suggestion.thisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
                    print("[SESSION][PLAN] suggestion loaded exerciseId=\(exerciseId) preview=\"\(planPreview)\"")
                    #endif
                    exerciseRefreshToken = UUID()
                    isLoadingCoaching = false
                }
            }
        }
    }

    private func cleanExerciseName(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard OpenAIConfig.isAIAvailable else {
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
                        showTimerDoneOverlay = false
                        RestTimerNotifier.cancelNotification()
                        RestTimerNotifier.stopCompletion()
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
                        showTimerDoneOverlay = false
                        RestTimerNotifier.cancelNotification()
                        RestTimerNotifier.scheduleNotification(in: total)
                        let endsAt = Date().addingTimeInterval(TimeInterval(total))
                        RestTimerLiveActivityController.start(endsAt: endsAt, exerciseName: currentExercise.name)
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
            .atlasBackground()
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
            .atlasBackground()
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

    private func presentPicker() {
        pickerWeightText = setDraft.weight
        pickerReps = Int(setDraft.reps) ?? 0
        pickerUnit = preferredUnit
        pickerTag = SetTag(rawValue: setDraft.tag) ?? .W
        showPickerSheet = true
    }

    private func setLine(_ set: SetLog) -> String {
        WorkoutSessionFormatter.formatSetLine(set: set, preferred: preferredUnit)
    }

    private func weightText(for set: SetLog) -> String {
        guard let weightKg = set.weightKg else { return "--" }
        return WeightFormatter.format(weightKg, unit: preferredUnit)
    }

    private struct SetEntrySheetView: View {
        @Binding var weightText: String
        @Binding var reps: Int
        @Binding var unit: WorkoutUnits
        @Binding var tag: SetTag
        let onChange: () -> Void
        let onLog: (Double?, Int, SetTag) -> Void
        let preferredUnit: WorkoutUnits
        let onUnitChange: (WorkoutUnits) -> Void

        @Environment(\.dismiss) private var dismiss
        @FocusState private var weightFieldFocused: Bool

        var body: some View {
            NavigationStack {
                VStack(spacing: 24) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 40, height: 4)
                    .padding(.top, 4)

                HStack {
                    Spacer()
                    Text("Set Entry")
                        .appFont(.title3, weight: .bold)
                    Spacer()
                    AtlasPillButton("Log") {
                        logAndDismiss()
                    }
                    .tint(.primary)
                    .frame(height: 34)
                }

                unitToggle
                tagSelector

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weight")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($weightFieldFocused)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                            )
                        Text(unit == .kg ? "kg" : "lb")
                            .appFont(.body, weight: .semibold)
                            .monospacedDigit()
                            .padding(.trailing, 4)
                    }
                }

                VStack(alignment: .center, spacing: 8) {
                    Text("Reps")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { reps },
                        set: { reps = $0; onChange() }
                    )) {
                        ForEach(0...50, id: \.self) { num in
                            Text("\(num)")
                                .tag(num)
                                .appFont(.title, weight: .bold)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(maxWidth: .infinity)

                Text("Values are stored in kilograms for history.")
                    .appFont(.footnote, weight: .regular)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
        }
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFieldFocused = false }
                    .appFont(.footnote, weight: .semibold)
            }
        }
    }

    private var unitToggle: some View {
        HStack {
            Text("Unit")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 8) {
                unitButton(.kg)
                unitButton(.lb)
            }
        }
    }

    private func unitButton(_ target: WorkoutUnits) -> some View {
        Button {
            unit = target
            onChange()
            onUnitChange(target)
        } label: {
            Text(target == .kg ? "kg" : "lb")
                .appFont(.body, weight: .semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.white.opacity(unit == target ? 0.16 : 0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func logAndDismiss() {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(trimmed) ?? 0
        let clamped = max(0, min(parsed, unit == .kg ? 900 : 2000))
        let kgValue = unit == .kg ? clamped : clamped / WorkoutSessionFormatter.kgToLb
        Haptics.playMediumImpact()
        onLog(kgValue.isNaN ? nil : kgValue, reps, tag)
        dismiss()
    }

    private var tagSelector: some View {
        HStack(spacing: 10) {
            tagButton(.W, label: "Warmup")
            tagButton(.S, label: "Standard")
            tagButton(.DS, label: "Drop")
        }
    }

    private func tagButton(_ value: SetTag, label: String) -> some View {
        Button {
            tag = value
            onChange()
        } label: {
            Text(label)
                .appFont(.footnote, weight: .semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.white.opacity(tag == value ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
}

private struct SetLogSheetView: View {
    let sets: [SetLog]
    let weightText: (SetLog) -> String
    let onDelete: (SetLog) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sets, id: \.id) { set in
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
                                        Text(weightText(set))
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
                                    Button(role: .destructive) {
                                        onDelete(set)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .id(set.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: sets.count) { _, _ in
                    if let last = sets.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("All Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .atlasBackgroundTheme(.workout)
            .atlasBackground()
        }
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
