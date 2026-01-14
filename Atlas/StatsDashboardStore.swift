import Foundation
import SwiftUI
import Combine

@MainActor
final class StatsDashboardStore: ObservableObject {
    @Published var mode: StatsMode = .strength {
        didSet { recomputeIfReady() }
    }
    @Published var range: StatsRange = .fourWeeks {
        didSet { recomputeIfReady() }
    }
    @Published var filter: StatsExerciseFilter = .allExercises {
        didSet { recomputeIfReady() }
    }
    @Published var dashboard: StatsDashboardResult = .empty(mode: .strength, range: .fourWeeks, filter: .allExercises)
    @Published var isLoading: Bool = false

    @AppStorage("pinned_exercise_ids") private var pinnedJSON: String = "[]"

    private var sessions: [SessionData] = []
    private var preferredUnit: WorkoutUnits = .kg
    private var cache: [String: (Date, StatsDashboardResult)] = [:]
    private let cacheTTL: TimeInterval = 45

    var pinnedLifts: [String] {
        get {
            guard let data = pinnedJSON.data(using: .utf8) else { return [] }
            let decoded = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            return decoded
        }
        set {
            let normalized = newValue.map { normalizeExerciseName($0) }
            if let data = try? JSONEncoder().encode(normalized), let string = String(data: data, encoding: .utf8) {
                pinnedJSON = string
            }
            recomputeIfReady()
        }
    }

    var availableExercises: [String] {
        var counts: [String: Int] = [:]
        for session in sessions {
            for exercise in session.exercises {
                counts[exercise.name, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    func updatePreferredUnit(_ unit: WorkoutUnits) {
        preferredUnit = unit
        recomputeIfReady()
    }

    func updateSessions(_ sessions: [WorkoutSession]) {
        self.sessions = sessions.map { session in
            let exercises = session.exercises.map { exercise in
                ExerciseData(
                    name: exercise.name,
                    orderIndex: exercise.orderIndex,
                    sets: exercise.sets.map { set in
                        SetData(tagRaw: set.tagRaw, weightKg: set.weightKg, reps: set.reps, createdAt: set.createdAt)
                    }
                )
            }
            return SessionData(
                id: session.id,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                isHidden: session.isHidden,
                totalSets: session.totalSets,
                durationSeconds: session.durationSeconds,
                exercises: exercises
            )
        }
        recomputeIfReady()
    }

    func togglePin(exerciseName: String) {
        var pins = pinnedLifts
        let normalized = normalizeExerciseName(exerciseName)
        if pins.contains(normalized) {
            pins.removeAll { $0 == normalized }
        } else {
            pins.append(normalized)
        }
        pinnedLifts = pins
    }

    func recomputeIfReady() {
        guard !sessions.isEmpty else {
            dashboard = .empty(mode: mode, range: range, filter: filter)
            return
        }
        recompute()
    }

    private func recompute() {
        let key = cacheKey()
        if let cached = cache[key], Date().timeIntervalSince(cached.0) < cacheTTL {
            dashboard = cached.1
            return
        }

        let inputSessions = sessions
        let pins = pinnedLifts
        let selectedMode = mode
        let selectedRange = range
        let selectedFilter = filter
        let unit = preferredUnit

        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StatsMetricEngine.computeDashboard(
                    sessions: inputSessions,
                    pinnedLifts: pins,
                    mode: selectedMode,
                    range: selectedRange,
                    filter: selectedFilter,
                    preferredUnit: unit
                )
            }.value

            self.dashboard = result
            self.cache[key] = (Date(), result)
            self.isLoading = false
        }
    }

    private func cacheKey() -> String {
        let pins = pinnedLifts.sorted().joined(separator: "|")
        return "\(mode.rawValue)-\(range.rawValue)-\(filter.rawValue)-\(pins)"
    }

    private func normalizeExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
