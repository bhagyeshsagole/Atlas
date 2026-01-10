import Foundation
import Combine

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var week: StatsMetrics = .empty(.week)
    @Published private(set) var month: StatsMetrics = .empty(.month)
    @Published private(set) var all: StatsMetrics = .empty(.all)

    func metrics(for lens: StatsLens) -> StatsMetrics {
        switch lens {
        case .week: return week
        case .month: return month
        case .all: return all
        }
    }

    func setMetrics(_ metrics: StatsMetrics) {
        switch metrics.lens {
        case .week: week = metrics
        case .month: month = metrics
        case .all: all = metrics
        }
    }

    func scheduleRecompute() {
        // noop placeholder; hook your background compute here.
    }

    func updateSessions(_ sessions: [WorkoutSession]) {
        // placeholder hook for future compute; keeps API stable.
    }
}
