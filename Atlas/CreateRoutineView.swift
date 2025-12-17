//
//  CreateRoutineView.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//

import SwiftUI

struct CreateRoutineView: View {
    @State private var title: String = ""
    @State private var rawWorkouts: String = ""
    @State private var isParsing = false
    @State private var isGenerating = false
    @State private var alertMessage: String?
    @FocusState private var focusedField: Field?

    let onGenerate: (String, [ParsedWorkout]) -> Void

    private enum Field {
        case title
        case workoutText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Routine Title")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    TextField("Push Day", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .tint(.primary)
                        .focused($focusedField, equals: .title)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Workouts")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $rawWorkouts)
                            .frame(minHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .tint(.primary)
                            .focused($focusedField, equals: .workoutText)
                        if rawWorkouts.isEmpty {
                            Text("lat pulldown x 3 10-12 and shoulder press x 3 10-12")
                                .appFont(.body, weight: .regular)
                                .foregroundStyle(.secondary.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 12)
                        }
                    }
                }

                Button {
                    generate()
                } label: {
                    Text(isParsing ? "Generating…" : "Generate")
                        .appFont(.pill, weight: .semibold)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(PressableGlassButtonStyle())
                .disabled(isGenerating)
            }
            .padding(AppStyle.contentPaddingLarge)
        }
        .scrollIndicators(.hidden)
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
                    onGenerate(name, workouts)
                }
            } catch let error as RoutineAIService.RoutineAIError {
                await MainActor.run { focusedField = nil }
                switch error {
                case .missingAPIKey:
                    DispatchQueue.main.async {
                        alertMessage = "Missing API key. Add it in LocalSecrets.openAIAPIKey."
                    }
                case .openAIRequestFailed(let status, let message):
                    DispatchQueue.main.async {
                        if let status {
                            alertMessage = "OpenAI error (\(status)). \(message)"
                        } else {
                            alertMessage = message
                        }
                    }
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
