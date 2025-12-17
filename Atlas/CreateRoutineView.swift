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
    @State private var alertMessage: String?

    let onGenerate: (String, [ParsedWorkout]) -> Void

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
                .disabled(isParsing)
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
        guard !isParsing else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Routine" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = rawWorkouts.trimmingCharacters(in: .whitespacesAndNewlines)
        isParsing = true
        Task {
            do {
                let workouts = try await RoutineAIService.parseWorkouts(from: input, routineTitleHint: name)
                await MainActor.run {
                    isParsing = false
                    guard !workouts.isEmpty else {
                        alertMessage = "No workouts found. Please describe at least one exercise."
                        return
                    }
                    onGenerate(name, workouts)
                }
            } catch let error as RoutineAIService.RoutineAIError {
                await MainActor.run {
                    isParsing = false
                    switch error {
                    case .missingAPIKey:
                        alertMessage = "Missing API key. Add it in LocalSecrets.openAIAPIKey."
                    case .openAIRequestFailed(let status, let message):
                        if let status {
                            alertMessage = "OpenAI error (\(status)). Check key/quota/network. \(message)"
                        } else {
                            alertMessage = "OpenAI error. Check key/quota/network. \(message)"
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isParsing = false
                    alertMessage = "Unexpected error: \(error.localizedDescription)"
                }
            }
        }
    }
}
