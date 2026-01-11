import Foundation
import Combine
import SwiftData

@MainActor
final class WorkoutSessionPreloader: ObservableObject {
    enum Phase {
        case idle
        case loading
        case ready
        case failed(String)
    }

    struct CacheEntry {
        let timestamp: Date
        let suggestions: [UUID: RoutineAIService.ExerciseSuggestion]
        let lastLines: [UUID: [String]]
        let lastDates: [UUID: Date?]
        let plans: [UUID: String]
    }

    private static var cache: [UUID: CacheEntry] = [:]
    private static let ttl: TimeInterval = 600 // 10 minutes

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var suggestions: [UUID: RoutineAIService.ExerciseSuggestion] = [:]
    @Published private(set) var lastLines: [UUID: [String]] = [:]
    @Published private(set) var lastDates: [UUID: Date?] = [:]
    @Published private(set) var plans: [UUID: String] = [:]

    private let routine: Routine
    private var historyStore: HistoryStore?
    private var modelContext: ModelContext?
    private var preloadTask: Task<Void, Never>?

    init(routine: Routine) {
        self.routine = routine
    }

    func configure(historyStore: HistoryStore, modelContext: ModelContext) {
        self.historyStore = historyStore
        self.modelContext = modelContext
    }

    func startPrefetch(preferredUnit: WorkoutUnits) {
        guard preloadTask == nil else { return }
        guard let historyStore, let modelContext else { return }

        // Cache hit
        if let entry = Self.cache[routine.id], Date().timeIntervalSince(entry.timestamp) < Self.ttl {
            suggestions = entry.suggestions
            lastLines = entry.lastLines
            lastDates = entry.lastDates
            plans = entry.plans
            phase = .ready
            return
        }

        phase = .loading
        let exercises = routine.workouts
        preloadTask = Task { [weak self] in
            guard let self else { return }
            async let historyTask: Void = preloadHistory(exercises: exercises, preferredUnit: preferredUnit, modelContext: modelContext)
            async let aiTask: Void = preloadAI(exercises: exercises, preferredUnit: preferredUnit)
            _ = await (historyTask, aiTask)
            await MainActor.run {
                Self.cache[routine.id] = CacheEntry(
                    timestamp: Date(),
                    suggestions: suggestions,
                    lastLines: lastLines,
                    lastDates: lastDates,
                    plans: plans
                )
                phase = .ready
                print("[Preload] ready routine=\(routine.id) suggestions=\(suggestions.count) history=\(lastLines.count)")
            }
        }
    }

    func cancel() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    private func preloadHistory(exercises: [RoutineWorkout], preferredUnit: WorkoutUnits, modelContext: ModelContext) async {
        var lines: [UUID: [String]] = [:]
        var dates: [UUID: Date?] = [:]
        var plansMap: [UUID: String] = [:]
        for workout in exercises {
            let log = WorkoutSessionHistory.latestCompletedExerciseLog(
                for: workout.name,
                excluding: nil,
                context: modelContext
            )
            dates[workout.id] = log?.session?.endedAt ?? log?.session?.startedAt
            if let log {
                lines[workout.id] = WorkoutSessionFormatter.lastSessionLines(for: log, preferred: preferredUnit)
                plansMap[workout.id] = WorkoutSessionHistory.guidanceRange(from: log, displayUnit: preferredUnit)
            }
        }
        await MainActor.run {
            self.lastLines = lines
            self.lastDates = dates
            self.plans = plansMap
            print("[Preload] history ready \(lines.count)")
        }
    }

    private func preloadAI(exercises: [RoutineWorkout], preferredUnit: WorkoutUnits) async {
        var suggestionsMap: [UUID: RoutineAIService.ExerciseSuggestion] = [:]
        for workout in exercises {
            let suggestion = await RoutineAIService.generateExerciseCoaching(
                routineTitle: routine.name,
                routineId: routine.id,
                exerciseName: workout.name,
                lastSessionSetsText: "",
                lastSessionDate: nil,
                preferredUnit: preferredUnit
            )
            suggestionsMap[workout.id] = suggestion
        }
        await MainActor.run {
            self.suggestions = suggestionsMap
            print("[Preload] ai ready \(suggestionsMap.count)")
        }
    }
}
