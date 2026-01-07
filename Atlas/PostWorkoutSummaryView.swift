//
//  PostWorkoutSummaryView.swift
//  Atlas
//
//  What this file is:
//  - Post-session screen that shows AI-generated or cached summaries for a completed workout.
//
//  Where it’s used:
//  - Presented from `WorkoutSessionView` after ending a session.
//
//  Key concepts:
//  - Fetches the stored session by ID using SwiftData and reuses cached AI text to avoid repeat calls.
//  - Uses `@AppStorage` to format weight units consistently.
//
//  Safe to change:
//  - Text layout, spacing, or fallback copy for missing summaries.
//
//  NOT safe to change:
//  - Removing the cache check before calling AI; it would trigger unnecessary network calls.
//  - Formatting lines without keeping kg/lb conversions; totals rely on both units.
//
//  Common bugs / gotchas:
//  - Forgetting to handle empty `aiPostSummaryJSON` leaves the screen in a loading state.
//  - Fetch predicates must stay in sync with stored session IDs or summaries will not load.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Post-Workout Summary (AI)
//
import SwiftUI
import SwiftData

struct PostWorkoutSummaryView: View {
    let sessionID: UUID
    var onDone: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = "lb"

    @State private var session: WorkoutSession? // Loaded SwiftData session to display.
    @State private var payload: PostWorkoutSummaryPayload? // Decoded AI JSON payload.
    @State private var isLoading = false // Controls loading state text.
    @State private var errorMessage: String?
    @State private var renderedText: String = "" // Cached formatted summary text.

    /// VISUAL TWEAK: Change `bodyLineSpacing` to make the text tighter/looser.
    private let bodyLineSpacing: CGFloat = 6
    /// VISUAL TWEAK: Change `titleScale` to make routine name bigger/smaller.
    private let titleScale: CGFloat = 1.0
    /// VISUAL TWEAK: Toggle `showsIndicators` to true if you ever want scroll bar back.
    private let showsIndicators: Bool = false
    /// VISUAL TWEAK: Adjust `minScale` if text feels too tight.
    private let minScale: CGFloat = 0.9

    /// DEV NOTE: This screen caches `aiPostSummaryJSON` and `aiPostSummaryText` so the API is called once per session.
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sessionTitle)
                    .appFont(.title, weight: .semibold)
                    .scaleEffect(titleScale, anchor: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(minScale)
                Text(payload?.sessionDate ?? formattedSessionDate())
                    .appFont(.body, weight: .regular)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(minScale)
            }

            ScrollView(.vertical, showsIndicators: showsIndicators) {
                Text(contentText())
                    .appFont(.body, weight: .regular)
                    .lineSpacing(bodyLineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(AppStyle.contentPaddingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            AtlasPillButton("Done") {
                dismiss()
                onDone()
            }
            .padding(.horizontal, AppStyle.contentPaddingLarge)
            .padding(.bottom, AppStyle.startButtonBottomPadding)
        }
        .task {
            await load()
        }
    }

    private func contentText() -> String {
        if !renderedText.isEmpty {
            return renderedText
        }
        if isLoading {
            return "Generating summary…"
        }
        if let errorMessage {
            return "Summary unavailable.\n\(errorMessage)"
        }
        return "Summary unavailable."
    }

    private func computeTotals(session: WorkoutSession) -> (volumeKg: Double, sets: Int, reps: Int) {
        var volume: Double = 0
        var setsCount = 0
        var repsCount = 0
        for exercise in session.exercises {
            for set in exercise.sets {
                setsCount += 1
                repsCount += set.reps
                if let w = set.weightKg {
                    volume += w * Double(set.reps)
                }
            }
        }
        return (volume, setsCount, repsCount)
    }

    private var sessionTitle: String {
        session?.routineTitle.isEmpty == false ? session!.routineTitle : "Workout Summary"
    }

    private func formattedSessionDate() -> String {
        guard let session else { return "Summary" }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL dd, yyyy (EEEE)"
        return formatter.string(from: session.startedAt)
    }

    private func buildDisplayText(with payload: PostWorkoutSummaryPayload?, for session: WorkoutSession) -> String {
        let totals = computeTotals(session: session)
        let volumeKg = String(format: "%.0f kg", totals.volumeKg)
        let volumeLb = String(format: "%.0f lb", totals.volumeKg * WorkoutSessionFormatter.kgToLb)
        let trainingVolumeLine = "Training volume: \(volumeKg) | \(volumeLb)"
        let setsRepsLine = "Sets / Reps: \(totals.sets) sets / \(totals.reps) reps"

        let ratingValue = payload?.rating.map { String(format: "%.1f", $0) } ?? "—"
        let insight = (payload?.insight?.isEmpty == false ? payload?.insight : nil) ?? "Summary unavailable."
        let ratingLine = "\(ratingValue)/10 — \(insight)"

        let prs = Array((payload?.prs ?? []).prefix(2)).filter { !$0.isEmpty }
        let prLines: [String]
        if prs.isEmpty {
            prLines = ["PRs: None"]
        } else {
            prLines = ["PRs:"] + prs.map { "• \($0)" }
        }

        let improvementsRaw = Array((payload?.improvements ?? []).prefix(3)).filter { !$0.isEmpty }
        let improvements: [String]
        if improvementsRaw.isEmpty {
            improvements = fallbackImprovements(for: session)
        } else {
            improvements = ["Improvements next time:"] + improvementsRaw.map { "• \($0)" }
        }

        var lines: [String] = [
            trainingVolumeLine,
            setsRepsLine,
            "",
            ratingLine,
            ""
        ]
        lines.append(contentsOf: prLines)
        lines.append("")
        lines.append(contentsOf: improvements)

        return lines.joined(separator: "\n")
    }

    private func fallbackImprovements(for session: WorkoutSession) -> [String] {
        let name = session.exercises.first?.name ?? "First lift"
        return [
            "Improvements next time:",
            "• \(name): match last top set and add 1–2 reps if strong.",
            "• Add one accessory if time allows."
        ]
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
        }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let loadedSession = try? modelContext.fetch(descriptor).first
        await MainActor.run {
            self.session = loadedSession
        }
        guard let session = loadedSession else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Session not found."
            }
            return
        }

        if !session.aiPostSummaryText.isEmpty {
            await MainActor.run {
                renderedText = session.aiPostSummaryText
                isLoading = false
            }
            if let data = session.aiPostSummaryJSON.data(using: .utf8),
               let payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: data) {
                await MainActor.run {
                    self.payload = payload
                }
            }
            return
        }

        if !session.aiPostSummaryJSON.isEmpty,
           let data = session.aiPostSummaryJSON.data(using: .utf8),
           let storedPayload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: data) {
            let text = buildDisplayText(with: storedPayload, for: session)
            await MainActor.run {
                payload = storedPayload
                renderedText = text
                session.aiPostSummaryText = text
                try? modelContext.save()
                isLoading = false
            }
            return
        }

        let previousLogs = try? modelContext.fetch(FetchDescriptor<ExerciseLog>(
            predicate: #Predicate { log in
                log.session?.isCompleted == true && log.session?.id != sessionID
            },
            sortBy: [SortDescriptor(\ExerciseLog.session?.startedAt, order: .reverse)]
        ))
        let previousByExercise: [String: ExerciseLog?] = (previousLogs ?? []).reduce(into: [:]) { dict, log in
            let key = log.name.lowercased()
            if dict[key] == nil {
                dict[key] = log
            }
        }

        let unitPref = WorkoutUnits(from: weightUnit)
        if let result = await RoutineAIService.generatePostWorkoutSummary(session: session, previousSessionsByExercise: previousByExercise, unitPreference: unitPref) {
            let text = buildDisplayText(with: result.payload, for: session)
            await MainActor.run {
                payload = result.payload
                renderedText = text
                session.aiPostSummaryJSON = result.rawJSON
                session.aiPostSummaryText = text
                session.aiPostSummaryGeneratedAt = Date()
                session.aiPostSummaryModel = result.model
                try? modelContext.save()
                isLoading = false
            }
        } else {
            let fallbackText = buildDisplayText(with: nil, for: session)
            await MainActor.run {
                renderedText = fallbackText
                session.aiPostSummaryText = fallbackText
                try? modelContext.save()
                isLoading = false
                errorMessage = "Unable to generate summary."
            }
        }
    }
}
