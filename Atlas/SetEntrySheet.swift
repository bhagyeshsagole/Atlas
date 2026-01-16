//
//  SetEntrySheet.swift
//  Atlas
//
//  Full-screen Add Set sheet with smart features:
//  - Auto-detect tag (warmup/working/drop)
//  - Auto progression suggestion
//  - PR detection and nudge
//  - Fatigue guardrail
//  - Target remaining display
//  - Numbered sets with meaningful notes
//

import SwiftUI
import SwiftData

struct SetEntrySheet: View {
    // MARK: - Bindings
    @Binding var weightText: String
    @Binding var reps: Int
    @Binding var unit: WorkoutUnits
    @Binding var tag: SetTag

    // MARK: - Data
    let exerciseName: String
    let thisSessionSets: [SetLog]
    let lastSessionSets: [SetLog]
    let lastSessionDate: Date?
    let planText: String
    let historicalWorkingSets: [SetLog] // Working sets from last 8 weeks for this exercise
    let historicalBestWeightAt5Plus: Double?
    let historicalBestVolume: Double?

    // MARK: - Callbacks
    let onChange: () -> Void
    let onLog: (Double?, Int, SetTag) -> Void
    let onDelete: (SetLog) -> Void
    let preferredUnit: WorkoutUnits

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var weightFieldFocused: Bool

    // MARK: - Layout Constants
    private let closeButtonSize: CGFloat = 36

    // MARK: - Computed Properties

    private var sortedThisSessionSets: [SetLog] {
        thisSessionSets.sorted { $0.createdAt < $1.createdAt }
    }

    private var workingSetsLogged: Int {
        thisSessionSets.filter { $0.tag == "S" }.count
    }

    private var targetRemaining: SetAdvisor.TargetRemaining {
        SetAdvisor.calculateTargetRemaining(
            planText: planText,
            workingSetsLogged: workingSetsLogged
        )
    }

    private var enteredWeightKg: Double? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(trimmed), parsed > 0 else { return nil }
        return preferredUnit == .kg ? parsed : parsed / WorkoutSessionFormatter.kgToLb
    }

    private var progressionSuggestion: SetAdvisor.ProgressionSuggestion? {
        let lastBest = lastSessionSets
            .filter { $0.tag == "S" }
            .max { a, b in
                let aWeight = a.weightKg ?? 0
                let bWeight = b.weightKg ?? 0
                if aWeight == bWeight { return a.reps < b.reps }
                return aWeight < bWeight
            }

        guard let best = lastBest else { return nil }

        let setData = SetAdvisor.SetData(
            weightKg: best.weightKg,
            reps: best.reps,
            tag: best.tag,
            createdAt: best.createdAt
        )

        return SetAdvisor.suggestProgression(
            lastSessionBestWorkingSet: setData,
            targetRepRangeUpper: targetRemaining.repRangeUpper,
            isMetricUnit: preferredUnit == .kg
        )
    }

    private var fatigue: (isFatigued: Bool, message: String?) {
        let setDataArray = thisSessionSets.map {
            SetAdvisor.SetData(weightKg: $0.weightKg, reps: $0.reps, tag: $0.tag, createdAt: $0.createdAt)
        }
        return SetAdvisor.detectFatigue(
            thisSessionSets: setDataArray,
            targetRepRangeLower: targetRemaining.repRangeLower
        )
    }

    private var prStatus: (isPR: Bool, isCloseToPR: Bool) {
        SetAdvisor.checkPRStatus(
            weightKg: enteredWeightKg,
            reps: reps,
            historicalBestWeightAt5Plus: historicalBestWeightAt5Plus,
            historicalBestVolume: historicalBestVolume
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppStyle.sectionSpacing) {
                    headerSection
                    tagChipsSection
                    weightInputSection
                    repsSection
                    smartStripSection

                    if !sortedThisSessionSets.isEmpty {
                        thisSessionSection
                    }

                    if !lastSessionSets.isEmpty {
                        lastSessionSection
                    }

                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, AppStyle.contentPaddingLarge)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                footerSection
            }
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFieldFocused = false }
                    .appFont(.footnote, weight: .semibold)
            }
        }
        .onAppear {
            applyAutoDetectTag()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Color.clear.frame(width: closeButtonSize)

            Spacer()

            VStack(spacing: 4) {
                Text("Add Set")
                    .appFont(.title3, weight: .bold)
                Text(exerciseName)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                Haptics.playLightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tag Chips Section

    private var tagChipsSection: some View {
        HStack(spacing: 10) {
            tagChip(.W, label: "Warmup")
            tagChip(.S, label: "Working")
            tagChip(.DS, label: "Drop")
        }
    }

    private func tagChip(_ value: SetTag, label: String) -> some View {
        Button {
            tag = value
            Haptics.playLightTap()
            onChange()
        } label: {
            Text(label)
                .appFont(.footnote, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(Color.white.opacity(tag == value ? 0.18 : 0.08))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weight Input Section

    private var weightInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFieldFocused)
                    .textFieldStyle(.plain)
                    .appFont(.title3, weight: .semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.08))
                    )
                    .onChange(of: weightText) { _, _ in
                        applyAutoDetectTag()
                    }

                Text(preferredUnit.label)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.06))
                    )
            }
        }
    }

    // MARK: - Reps Section

    private var repsSection: some View {
        VStack(alignment: .center, spacing: 4) {
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
            .frame(height: 120)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Smart Strip Section

    private var smartStripSection: some View {
        HStack(spacing: 10) {
            // Chip A: Auto Progression
            if let suggestion = progressionSuggestion {
                smartChip(
                    icon: "arrow.up.right",
                    label: "Auto: \(suggestion.reason)",
                    isHighlighted: false
                ) {
                    applyProgression(suggestion)
                }
            }

            // Chip B: PR Nudge OR Fatigue Guardrail (only one shows)
            if prStatus.isPR {
                smartChip(
                    icon: "trophy.fill",
                    label: "PR attempt",
                    isHighlighted: true
                ) {
                    // Already entered, just acknowledge
                    Haptics.playLightTap()
                }
            } else if prStatus.isCloseToPR {
                smartChip(
                    icon: "trophy",
                    label: "Close to PR",
                    isHighlighted: false
                ) {
                    Haptics.playLightTap()
                }
            } else if fatigue.isFatigued {
                smartChip(
                    icon: "exclamationmark.triangle",
                    label: "Fatigue detected",
                    isHighlighted: false
                ) {
                    // Could show alert, for now just haptic
                    Haptics.playLightTap()
                }
            }

            Spacer()
        }
        .frame(minHeight: 36)
    }

    private func smartChip(
        icon: String,
        label: String,
        isHighlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .appFont(.caption, weight: .semibold)
            }
            .foregroundStyle(isHighlighted ? .yellow : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Color.white.opacity(isHighlighted ? 0.15 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - This Session Section

    private var thisSessionSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            Text("This Session")
                .appFont(.section, weight: .bold)

            LazyVStack(spacing: 8) {
                ForEach(Array(sortedThisSessionSets.enumerated()), id: \.element.id) { index, set in
                    thisSessionSetRow(set, index: index)
                }
            }
        }
    }

    private func thisSessionSetRow(_ set: SetLog, index: Int) -> some View {
        let setData = sortedThisSessionSets.map {
            SetAdvisor.SetData(weightKg: $0.weightKg, reps: $0.reps, tag: $0.tag, createdAt: $0.createdAt)
        }
        let currentSetData = SetAdvisor.SetData(
            weightKg: set.weightKg,
            reps: set.reps,
            tag: set.tag,
            createdAt: set.createdAt
        )
        let note = SetAdvisor.generateSetNote(
            set: currentSetData,
            setIndex: index,
            allSessionSets: setData,
            historicalBestWeightAt5Plus: historicalBestWeightAt5Plus,
            historicalBestVolume: historicalBestVolume
        )

        return HStack(spacing: 12) {
            // Set number
            Text("Set \(index + 1)")
                .appFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            // Tag pill
            if let setTag = SetTag(rawValue: set.tag) {
                Text(tagDisplayName(setTag))
                    .appFont(.caption, weight: .bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            // Weight × Reps
            Text("\(WeightFormatter.format(set.weightKg, unit: preferredUnit)) × \(set.reps)")
                .appFont(.body, weight: .semibold)
                .monospacedDigit()

            // Note (if any)
            if let note {
                Text(note.text)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(note.isPR ? .yellow : .secondary)
            }

            Spacer()

            // Remove button
            Button(role: .destructive) {
                Haptics.playLightTap()
                onDelete(set)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(AppStyle.glassContentPadding)
        .atlasGlassCard()
    }

    // MARK: - Last Session Section

    private var lastSessionSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            HStack {
                Text("Last Session")
                    .appFont(.section, weight: .bold)

                if let date = lastSessionDate {
                    Spacer()
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVStack(spacing: 8) {
                ForEach(Array(lastSessionSets.prefix(6)), id: \.id) { set in
                    lastSessionSetRow(set)
                }
            }
        }
    }

    private func lastSessionSetRow(_ set: SetLog) -> some View {
        Button {
            Haptics.playLightTap()
            prefill(weight: set.weightKg, reps: set.reps, tag: SetTag(rawValue: set.tag) ?? .S)
        } label: {
            HStack(spacing: 12) {
                if let setTag = SetTag(rawValue: set.tag) {
                    Text(tagDisplayName(setTag))
                        .appFont(.caption, weight: .bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                Text("\(WeightFormatter.format(set.weightKg, unit: preferredUnit)) × \(set.reps)")
                    .appFont(.body, weight: .semibold)
                    .monospacedDigit()

                Spacer()

                Image(systemName: "arrow.up.left")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(AppStyle.glassContentPadding)
            .atlasGlassCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 8) {
            // Target remaining
            if targetRemaining.workingSetsRemaining > 0 {
                Text("Target remaining: \(targetRemaining.workingSetsRemaining) working sets (min)")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            } else if workingSetsLogged > 0 {
                Text("Target complete")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.green.opacity(0.8))
            }

            // Log Set button
            AtlasPillButton("Log Set") {
                logSet()
            }
            .padding(.horizontal, AppStyle.contentPaddingLarge)
        }
        .padding(.top, 12)
        .padding(.bottom, 34)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func applyAutoDetectTag() {
        let setDataArray = thisSessionSets.map {
            SetAdvisor.SetData(weightKg: $0.weightKg, reps: $0.reps, tag: $0.tag, createdAt: $0.createdAt)
        }
        let historicalSetData = historicalWorkingSets.map {
            SetAdvisor.SetData(weightKg: $0.weightKg, reps: $0.reps, tag: $0.tag, createdAt: $0.createdAt)
        }

        let suggestedTag = SetAdvisor.suggestTag(
            enteredWeightKg: enteredWeightKg,
            thisSessionSets: setDataArray,
            historicalWorkingSets: historicalSetData,
            lastUsedTag: thisSessionSets.last?.tag
        )

        if let newTag = SetTag(rawValue: suggestedTag), newTag != tag {
            tag = newTag
        }
    }

    private func applyProgression(_ suggestion: SetAdvisor.ProgressionSuggestion) {
        Haptics.playLightTap()

        if let weightKg = suggestion.weightKg {
            let displayValue = preferredUnit == .kg ? weightKg : weightKg * WorkoutSessionFormatter.kgToLb
            weightText = String(format: "%.1f", displayValue)
        }
        reps = suggestion.reps
        tag = .S // Progression is always for working sets
        onChange()
    }

    private func prefill(weight: Double?, reps: Int, tag: SetTag) {
        if let weight {
            let displayValue = preferredUnit == .kg ? weight : weight * WorkoutSessionFormatter.kgToLb
            weightText = String(format: "%.1f", displayValue)
        } else {
            weightText = ""
        }
        self.reps = reps
        self.tag = tag
        onChange()
    }

    private func logSet() {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(trimmed) ?? 0
        let clamped = max(0, min(parsed, unit == .kg ? 900 : 2000))
        let kgValue = unit == .kg ? clamped : clamped / WorkoutSessionFormatter.kgToLb

        // Check if this is a PR
        let isPR = SetAdvisor.checkPRStatus(
            weightKg: kgValue.isNaN || kgValue == 0 ? nil : kgValue,
            reps: reps,
            historicalBestWeightAt5Plus: historicalBestWeightAt5Plus,
            historicalBestVolume: historicalBestVolume
        ).isPR

        if isPR {
            Haptics.playSuccessHaptic()
        } else {
            Haptics.playMediumImpact()
        }

        onLog(kgValue.isNaN || kgValue == 0 ? nil : kgValue, reps, tag)
    }

    // MARK: - Helpers

    private func tagDisplayName(_ tag: SetTag) -> String {
        switch tag {
        case .W: return "Warmup"
        case .S: return "Working"
        case .DS: return "Drop"
        }
    }
}
