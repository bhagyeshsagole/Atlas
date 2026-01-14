//
//  ImportHistoryView.swift
//  Atlas
//
//  What this file is:
//  - UI for importing workout history from text logs or files.
//
//  Where it's used:
//  - Presented from Settings when user taps "Import Workout History".
//
//  Key concepts:
//  - Paste text or pick .txt file
//  - AI parses workout logs into structured sessions
//  - Preview with validation before import
//  - Idempotent import to avoid duplicates
//
//  Safe to change:
//  - UI layout, validation messaging, preview formatting.
//
//  NOT safe to change:
//  - Import logic without updating HistoryImportService.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var inputText: String = ""
    @State private var isParsing: Bool = false
    @State private var isImporting: Bool = false
    @State private var parsedSessions: [ImportedSession] = []
    @State private var errorMessage: String?
    @State private var importResult: (imported: Int, skipped: Int)?
    @State private var showingFilePicker = false

    var body: some View {
        ZStack {
            Color.clear
                .atlasBackground()
                .atlasBackgroundTheme(.workout)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    inputSection
                    errorSection
                    successSection
                    previewSection
                }
                .padding(AppStyle.contentPaddingLarge)
            }
        }
        .navigationTitle("Import History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workout Log")
                    .appFont(.section, weight: .bold)

                Text("Paste your workout history or pick a .txt file. The AI will parse your logs into structured workouts.")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                TextEditor(text: $inputText)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .scrollContentBackground(.hidden)
                    .appFont(.caption)

                HStack(spacing: 12) {
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                            Text("Pick File")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(isParsing || isImporting)

                    Button {
                        Task { await parseLog() }
                    } label: {
                        HStack(spacing: 8) {
                            if isParsing {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Parse")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing || isImporting)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red.opacity(0.8))
                        Text("Error")
                            .appFont(.body, weight: .bold)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    Text(errorMessage)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var successSection: some View {
        if let result = importResult {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.8))
                        Text("Import Complete")
                            .appFont(.body, weight: .bold)
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    Text("Imported \(result.imported) workout\(result.imported == 1 ? "" : "s")")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.primary)
                    if result.skipped > 0 {
                        Text("Skipped \(result.skipped) duplicate\(result.skipped == 1 ? "" : "s")")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !parsedSessions.isEmpty {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Preview")
                            .appFont(.section, weight: .bold)
                        Spacer()
                        Text("\(parsedSessions.count) session\(parsedSessions.count == 1 ? "" : "s")")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(parsedSessions) { session in
                        sessionPreview(session)
                        if session != parsedSessions.last {
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }

                    Button {
                        Task { await importSessions() }
                    } label: {
                        HStack(spacing: 8) {
                            if isImporting {
                                ProgressView()
                                    .tint(.primary)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import Workouts")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting || parsedSessions.filter({ $0.isValid }).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionPreview(_ session: ImportedSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.routineTitle)
                        .appFont(.body, weight: .bold)
                    Text(formatDate(session.date))
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: session.isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(session.isValid ? .green.opacity(0.8) : .red.opacity(0.8))
            }

            ForEach(session.exercises.prefix(3)) { exercise in
                Text("• \(exercise.name) (\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s"))")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            if session.exercises.count > 3 {
                Text("+ \(session.exercises.count - 3) more exercise\(session.exercises.count - 3 == 1 ? "" : "s")")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
    }

    private func parseLog() async {
        isParsing = true
        errorMessage = nil
        parsedSessions = []
        importResult = nil

        do {
            let sessions = try await HistoryImportService.parseWorkoutHistory(rawText: inputText)
            parsedSessions = sessions
        } catch {
            errorMessage = error.localizedDescription
        }

        isParsing = false
    }

    private func importSessions() async {
        isImporting = true
        errorMessage = nil
        importResult = nil

        do {
            let result = try HistoryImportService.importSessions(parsedSessions, to: modelContext)
            importResult = result
            if result.imported > 0 {
                // Clear input after successful import
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    inputText = ""
                    parsedSessions = []
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                // Ensure we have permission to access the file
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "Unable to access file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let content = try String(contentsOf: url, encoding: .utf8)
                inputText = content
                errorMessage = nil
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = "File picker error: \(error.localizedDescription)"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ImportHistoryView()
            .modelContainer(for: [WorkoutSession.self], inMemory: true)
    }
}
