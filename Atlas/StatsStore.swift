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
        MuscleCoverageScoring.computeBucketScores(sessions: sessions, range: lens)
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

}
