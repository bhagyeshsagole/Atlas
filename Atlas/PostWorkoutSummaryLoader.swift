import Foundation
import Combine
import SwiftData

@MainActor
final class PostWorkoutSummaryLoader: ObservableObject {
    @Published var session: WorkoutSession?
    @Published var payload: PostWorkoutSummaryPayload?
    @Published var isLoading = false
    @Published var isLoadingAI = false
    @Published var errorMessage: String?
    @Published var localSummaryLines: [String] = []
    @Published var aiSummaryText: String?

    func preload(sessionID: UUID, modelContext: ModelContext, unitPreference: WorkoutUnits) async {
        if session?.id == sessionID, isLoading == false, isLoadingAI == false { return }
        await load(sessionID: sessionID, modelContext: modelContext, unitPreference: unitPreference)
    }

    func load(sessionID: UUID, modelContext: ModelContext, unitPreference: WorkoutUnits) async {
        isLoading = true
        errorMessage = nil

        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let loadedSession = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == sessionID })
        session = loadedSession

        guard let session else {
            errorMessage = "Session not found."
            isLoading = false
            return
        }

        localSummaryLines = makeLocalSummary(for: session, unit: unitPreference)

        if session.aiPostSummaryJSON.isEmpty == false {
            payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: Data(session.aiPostSummaryJSON.utf8))
            aiSummaryText = payload.map { formattedAISummary(from: $0, unit: unitPreference, session: session) } ?? session.aiPostSummaryText
            isLoading = false
            return
        }

        // If we have cached text only, render it immediately.
        if session.aiPostSummaryText.isEmpty == false {
            aiSummaryText = session.aiPostSummaryText
            isLoading = false
            return
        }

        isLoadingAI = true
        Task {
            await generateAISummary(for: session, modelContext: modelContext, unitPreference: unitPreference)
        }
        isLoading = false
    }

    private func generateAISummary(for session: WorkoutSession, modelContext: ModelContext, unitPreference: WorkoutUnits) async {
        var previous: [String: ExerciseLog?] = [:]
        let uniqueNames = Set(session.exercises.map { $0.name })
        for name in uniqueNames {
            let log = WorkoutSessionHistory.latestCompletedExerciseLog(for: name, excluding: session.id, context: modelContext)
            previous[name] = log
        }

        let result = await RoutineAIService.generatePostWorkoutSummary(session: session, previousSessionsByExercise: previous, unitPreference: unitPreference)
        await MainActor.run {
            isLoadingAI = false
            guard let result else {
                errorMessage = "AI summary unavailable."
                return
            }
            payload = result.payload
            aiSummaryText = formattedAISummary(from: result.payload, unit: unitPreference, session: session)
            session.aiPostSummaryJSON = result.rawJSON
            session.aiPostSummaryModel = result.model
            session.aiPostSummaryGeneratedAt = Date()
            session.aiPostSummaryText = aiSummaryText ?? ""
            try? modelContext.save()
        }
    }

    private func makeLocalSummary(for session: WorkoutSession, unit: WorkoutUnits) -> [String] {
        var volume: Double = 0
        var sets: Int = 0
        var reps: Int = 0
        var exercisesPerformed: [String: Int] = [:]

        for exercise in session.exercises {
            let logged = exercise.sets.filter { $0.reps > 0 }
            guard !logged.isEmpty else { continue }
            exercisesPerformed[exercise.name, default: 0] += logged.count
            for set in logged {
                sets += 1
                reps += set.reps
                if let w = set.weightKg {
                    volume += w * Double(set.reps)
                }
            }
        }

        let volumeValue = unit == .kg ? volume : volume * WorkoutSessionFormatter.kgToLb
        let volumeText = String(format: "%.0f %@", volumeValue, unit == .kg ? "kg" : "lb")
        var lines: [String] = [
            "Volume: \(volumeText)",
            "Sets: \(sets)",
            "Reps: \(reps)"
        ]

        if exercisesPerformed.isEmpty {
            lines.append("Exercises: none logged")
        } else {
            let topExercises = exercisesPerformed.sorted { $0.value > $1.value }.prefix(3)
            let names = topExercises.map { "\($0.key) (\($0.value) sets)" }.joined(separator: ", ")
            lines.append("Exercises: \(names)")
        }
        return lines
    }

    private func formattedAISummary(from payload: PostWorkoutSummaryPayload, unit: WorkoutUnits, session: WorkoutSession) -> String {
        var lines: [String] = []
        if let rating = payload.rating {
            lines.append("Rating: \(String(format: "%.1f", rating))/10")
        }
        if let insight = payload.insight, !insight.isEmpty {
            lines.append("Insight: \(insight)")
        }
        if let prs = payload.prs, !prs.isEmpty {
            lines.append("PRs:")
            lines.append(contentsOf: prs.map { "• \($0)" })
        }
        if let improvements = payload.improvements, !improvements.isEmpty {
            lines.append("Next time:")
            lines.append(contentsOf: improvements.prefix(3).map { "• \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}
