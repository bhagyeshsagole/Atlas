//
//  SetEntrySheet.swift
//  Atlas
//
//  Redesigned Add Set sheet with embedded history, quick-fill, and iOS 26 glass styling.
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
    let bestRecentSet: SetLog?

    // MARK: - Callbacks
    let onChange: () -> Void
    let onLog: (Double?, Int, SetTag) -> Void
    let onDelete: (SetLog) -> Void
    let preferredUnit: WorkoutUnits

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @FocusState private var weightFieldFocused: Bool

    // MARK: - Layout Constants
    private let closeButtonSize: CGFloat = 32

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppStyle.sectionSpacing) {
                    headerSection
                    tagChipsSection
                    weightInputSection
                    repsSection

                    if hasQuickFillOptions {
                        quickFillSection
                    }

                    if !thisSessionSets.isEmpty {
                        thisSessionSection
                    }

                    if !lastSessionSets.isEmpty {
                        lastSessionSection
                    }

                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, AppStyle.contentPaddingLarge)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                footerCTA
            }
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFieldFocused = false }
                    .appFont(.footnote, weight: .semibold)
            }
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
            .frame(height: 120)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Fill Section

    private var hasQuickFillOptions: Bool {
        !thisSessionSets.isEmpty || bestRecentSet != nil
    }

    private var quickFillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Fill")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let lastSet = thisSessionSets.last {
                    quickFillChip(
                        label: "Last set",
                        weight: lastSet.weightKg,
                        reps: lastSet.reps,
                        tag: SetTag(rawValue: lastSet.tag) ?? .S
                    )
                }

                if let bestSet = bestRecentSet {
                    quickFillChip(
                        label: "Best recent",
                        weight: bestSet.weightKg,
                        reps: bestSet.reps,
                        tag: SetTag(rawValue: bestSet.tag) ?? .S
                    )
                }
            }
        }
    }

    private func quickFillChip(label: String, weight: Double?, reps: Int, tag: SetTag) -> some View {
        Button {
            Haptics.playLightTap()
            prefill(weight: weight, reps: reps, tag: tag)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(WeightFormatter.format(weight, unit: preferredUnit))
                        .appFont(.footnote, weight: .semibold)
                    Text("× \(reps)")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
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

    // MARK: - This Session Section

    private var thisSessionSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.subheaderSpacing) {
            Text("This Session")
                .appFont(.section, weight: .bold)

            LazyVStack(spacing: 8) {
                ForEach(thisSessionSets.sorted { $0.createdAt < $1.createdAt }, id: \.id) { set in
                    thisSessionSetRow(set)
                }
            }
        }
    }

    private func thisSessionSetRow(_ set: SetLog) -> some View {
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

    // MARK: - Footer CTA

    private var footerCTA: some View {
        VStack(spacing: 0) {
            AtlasPillButton("Log Set") {
                logSet()
            }
            .padding(.horizontal, AppStyle.contentPaddingLarge)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func logSet() {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(trimmed) ?? 0
        let clamped = max(0, min(parsed, unit == .kg ? 900 : 2000))
        let kgValue = unit == .kg ? clamped : clamped / WorkoutSessionFormatter.kgToLb

        Haptics.playMediumImpact()
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
