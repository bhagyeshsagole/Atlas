//
//  CreateRoutineView.swift
//  Atlas
//
//  What this file is:
//  - Routine creation form where users type workouts and trigger AI parsing/generation.
//
//  Where it’s used:
//  - Navigated from `ContentView` and `RoutineListView` to start building a new routine.
//
//  Called from:
//  - Pushed by `ContentView`/`RoutineListView`, then hands results to `ReviewRoutineView` via `onGenerate`.
//
//  Key concepts:
//  - `@State` stores form text and loading flags; `@FocusState` moves focus between fields.
//  - AI flow sets `isParsing`/`isGenerating` while waiting for OpenAI responses.
//
//  Safe to change:
//  - Placeholder text, button labels, or spacing; validation copy.
//
//  NOT safe to change:
//  - Removing trims or duplicate `focusedField` resets; errors rely on clearing focus before showing alerts.
//  - Skipping `isGenerating` guard; without it users can fire multiple overlapping AI calls.
//
//  Common bugs / gotchas:
//  - If you forget to clear `alertMessage`, the alert will keep reappearing.
//  - Empty input still triggers parsing unless you guard for it.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//

import SwiftUI

struct CreateRoutineView: View {
    @State private var title: String = ""
    @State private var rawWorkouts: String = ""
    @State private var isParsing = false // Shows loading state while AI is working.
    @State private var isGenerating = false // Prevents duplicate AI calls.
    @State private var alertMessage: String?
    @FocusState private var focusedField: Field? // Moves the caret between title and workout text.

    let onGenerate: (String, [ParsedWorkout]) -> Void

    private enum Field {
        case title
        case workoutText
    }

    var body: some View {
        ZStack {
            Color.clear
                .atlasBackground()
                .atlasBackgroundTheme(.workout)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Routine Title")
                            .appFont(.section, weight: .bold)
                            .foregroundStyle(.primary)
                        TextField("Push Day", text: $title)
                            .tint(.primary)
                            .focused($focusedField, equals: .title)
                            .disabled(isGenerating)
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workouts")
                            .appFont(.section, weight: .bold)
                            .foregroundStyle(.primary)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $rawWorkouts)
                                .frame(minHeight: 140)
                                .tint(.primary)
                                .focused($focusedField, equals: .workoutText)
                                .disabled(isGenerating)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .atlasGlassCard()
                            if rawWorkouts.isEmpty {
                                Text("lat pulldown x 3 10-12 and shoulder press x 3 10-12")
                                    .appFont(.body, weight: .regular)
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                            }
                        }
                    }

                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 10) {
                            if isGenerating {
                                ProgressView()
                                    .tint(.primary)
                                Text("Generating")
                                    .appFont(.body, weight: .semibold)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Generate")
                                    .appFont(.pill, weight: .semibold)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppStyle.glassContentPadding)
                        .background(
                            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
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

    private func generate() {
        guard !isGenerating else { return }
        #if DEBUG
        print("[AI] Generate tapped")
        #endif
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Routine" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = rawWorkouts.trimmingCharacters(in: .whitespacesAndNewlines)
        let isRequestMode = RoutineAIService.isLikelyWorkoutRequest(input)
        isParsing = true
        isGenerating = true
        Task {
            defer {
                Task { @MainActor in
                    isParsing = false
                    isGenerating = false
                    #if DEBUG
                    print("[AI] Generate finished")
                    #endif
                }
            }
            do {
                let cleanedTitle = await RoutineAIService.cleanRoutineTitle(rawTitle: name, workoutsPrompt: input)
                let workouts = try await RoutineAIService.parseWorkouts(from: input, routineTitleHint: name)
                if workouts.isEmpty {
                    await MainActor.run { focusedField = nil }
                    DispatchQueue.main.async {
                        if isRequestMode {
                            alertMessage = "AI returned an invalid format. Try rephrasing or specify equipment limits."
                        } else {
                            alertMessage = "No workouts found. Please describe at least one exercise."
                        }
                    }
                    return
                }
                await MainActor.run { focusedField = nil }
                try? await Task.sleep(nanoseconds: 150_000_000)
                await MainActor.run {
                    onGenerate(cleanedTitle, workouts)
                }
            } catch let error as RoutineAIError {
                await MainActor.run { focusedField = nil }
                switch error {
                case .missingAPIKey:
                    DispatchQueue.main.async {
                        alertMessage = "Missing API key. Add it in LocalSecrets.openAIAPIKey."
                    }
                case .httpStatus(let status, let body):
                    DispatchQueue.main.async {
                        let detail = body ?? "Request failed."
                        alertMessage = "OpenAI error (\(status)). \(detail)"
                    }
                case .requestFailed(let underlying):
                    DispatchQueue.main.async { alertMessage = underlying }
                default:
                    DispatchQueue.main.async { alertMessage = error.localizedDescription }
                }
            } catch {
                await MainActor.run { focusedField = nil }
                DispatchQueue.main.async {
                    alertMessage = "Unexpected error: \(error.localizedDescription)"
                }
            }
        }
    }
}
