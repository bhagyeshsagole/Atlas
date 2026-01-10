import Foundation
import Combine

@MainActor
final class StatsStore: ObservableObject {
    @Published var selectedRange: StatsLens = .week {
        didSet {
            if selectedRange != oldValue {
                recompute(for: selectedRange)
            }
        }
    }
    @Published private(set) var metricsByRange: [StatsLens: StatsMetrics] = [:]
    @Published private(set) var sessionCounts: [StatsLens: Int] = [:]
    @Published private(set) var week: StatsMetrics = .empty(.week)
    @Published private(set) var month: StatsMetrics = .empty(.month)
    @Published private(set) var all: StatsMetrics = .empty(.all)

    private var latestSessions: [WorkoutSession] = []

    func metrics(for lens: StatsLens) -> StatsMetrics {
        metricsByRange[lens] ?? StatsMetrics.empty(lens)
    }

    func setMetrics(_ metrics: StatsMetrics) {
        switch metrics.lens {
        case .week: week = metrics
        case .month: month = metrics
        case .all: all = metrics
        }
        metricsByRange[metrics.lens] = metrics
    }

    func setRange(_ lens: StatsLens) {
        selectedRange = lens
        recompute(for: lens)
    }

    func updateSessions(_ sessions: [WorkoutSession]) {
        latestSessions = sessions
        recomputeAll()
    }

    func recompute(for lens: StatsLens) {
        guard !latestSessions.isEmpty else {
            setMetrics(.empty(lens))
            sessionCounts[lens] = 0
            return
        }
        let now = Date()
        let (metrics, count) = computeMetrics(for: lens, sessions: latestSessions, now: now)
        setMetrics(metrics)
        sessionCounts[lens] = count
    }

    private func recomputeAll() {
        let now = Date()
        for lens in StatsLens.allCases {
            let (metrics, count) = computeMetrics(for: lens, sessions: latestSessions, now: now)
            setMetrics(metrics)
            sessionCounts[lens] = count
        }
    }

    private func computeMetrics(for lens: StatsLens, sessions: [WorkoutSession], now: Date) -> (StatsMetrics, Int) {
        let filtered = filter(sessions: sessions, for: lens, now: now)
        let workload = computeWorkload(from: filtered)
        let muscle = computeMuscleScores(for: lens, sessions: filtered)
        let coach = computeCoach(from: sessions, now: now)
        let metrics = StatsMetrics(lens: lens, muscle: muscle, workload: workload, coach: coach)
        return (metrics, filtered.count)
    }

    private func filter(sessions: [WorkoutSession], for lens: StatsLens, now: Date) -> [WorkoutSession] {
        sessions.filter { session in
            guard let ended = session.endedAt, session.totalSets > 0 else { return false }
            switch lens {
            case .all:
                return true
            case .week:
                if let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) {
                    return ended >= interval.start && ended <= interval.end
                }
                return true
            case .month:
                if let interval = Calendar.current.dateInterval(of: .month, for: now) {
                    return ended >= interval.start && ended <= interval.end
                }
                return true
            }
        }
    }

    private func computeWorkload(from sessions: [WorkoutSession]) -> WorkloadSummary {
        var volume: Double = 0
        var sets: Int = 0
        var reps: Int = 0
        for session in sessions {
            volume += session.volumeKg
            sets += session.totalSets
            reps += session.totalReps
        }
        return WorkloadSummary(volume: volume, sets: sets, reps: reps)
    }

    private func computeMuscleScores(for lens: StatsLens, sessions: [WorkoutSession]) -> [MuscleGroup: BucketScore] {
        var setCounts: [MuscleGroup: Double] = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0, 0.0) })
        for session in sessions {
            for exercise in session.exercises {
                let groups = classify(exerciseName: exercise.name)
                for set in exercise.sets {
                    let weight = setWeightMultiplier(for: set.tag)
                    for group in groups {
                        setCounts[group, default: 0] += weight
                    }
                }
            }
        }

        var scores: [MuscleGroup: BucketScore] = [:]
        let totalSets = setCounts.values.reduce(0, +)
        for group in MuscleGroup.allCases {
            let sets = setCounts[group] ?? 0
            switch lens {
            case .all:
                let progress = totalSets > 0 ? max(0, min(1, sets / totalSets)) : 0
                let scoreInt = Int((progress * 10).rounded())
                let reasons = sets > 0 ? ["\(group.displayName) made up \(Int(progress * 100))% of total sets"] : ["No sets logged"]
                let suggestions: [String]
                if totalSets == 0 {
                    suggestions = ["Add a primary \(group.displayName) lift to begin balancing coverage."]
                } else if sets < (totalSets * 0.2) {
                    suggestions = ["Add a primary \(group.displayName) lift to balance distribution", "Layer an accessory for \(group.displayName) to raise share"]
                } else {
                    suggestions = []
                }
                scores[group] = BucketScore(bucket: group, score0to10: scoreInt, progress01: progress, reasons: reasons, suggestions: suggestions)
            case .week, .month:
                let target = 10.0
                let progress = min(1.0, sets / target)
                let scoreInt = Int((progress * 10).rounded())
                let reasons = sets > 0 ? ["Logged \(Int(sets.rounded())) hard sets"] : ["No sets logged"]
                let suggestions = sets < target ? ["Add a primary \(group.displayName) lift", "Add an accessory to cover missing pattern"] : []
                scores[group] = BucketScore(bucket: group, score0to10: scoreInt, progress01: progress, reasons: reasons, suggestions: suggestions)
            }
        }
        return scores
    }

    private func classify(exerciseName: String) -> [MuscleGroup] {
        let lower = exerciseName.lowercased()
        var groups: [MuscleGroup] = []
        func contains(_ keywords: [String]) -> Bool {
            keywords.contains { lower.contains($0) }
        }
        if contains(["squat", "lunge", "leg press", "leg curl", "rdl", "deadlift", "hip thrust", "calf"]) {
            groups.append(.legs)
        }
        if contains(["bench", "press", "pushup", "push-up", "fly"]) {
            groups.append(.chest)
        }
        if contains(["row", "pulldown", "pull-down", "pullup", "pull-up"]) {
            groups.append(.back)
        }
        if contains(["shoulder", "ohp", "overhead", "lateral raise", "rear delt", "face pull"]) {
            groups.append(.shoulders)
        }
        if contains(["curl", "bicep", "biceps", "tricep", "triceps", "extension", "dip"]) {
            groups.append(.arms)
        }
        if contains(["plank", "crunch", "situp", "sit-up", "ab", "core"]) {
            groups.append(.core)
        }
        if groups.isEmpty {
            groups.append(.core)
        }
        return groups
    }

    private func computeCoach(from sessions: [WorkoutSession], now: Date) -> CoachSummary {
        let streak = streakCount(sessions: sessions, now: now)
        let next = "Keep going"
        let reason = streak > 0 ? "Streak \(streak) wks" : "Log 3 sessions this week"
        return CoachSummary(streakWeeks: streak, next: next, reason: reason)
    }

    private func streakCount(sessions: [WorkoutSession], now: Date) -> Int {
        let calendar = Calendar.current
        var weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var count = 0
        while true {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let filtered = sessions.filter { session in
                guard let ended = session.endedAt, session.totalSets > 0 else { return false }
                return ended >= weekStart && ended < weekEnd
            }
            if filtered.count >= 3 {
                count += 1
                if let previousWeek = calendar.date(byAdding: .day, value: -7, to: weekStart) {
                    weekStart = previousWeek
                } else {
                    break
                }
            } else {
                break
            }
        }
        return count
    }

    private func setWeightMultiplier(for tag: String) -> Double {
        switch SetTag(rawValue: tag) {
        case .W:
            return 0.5
        case .DS:
            return 0.75
        case .S, .none:
            return 1.0
        }
    }
}
