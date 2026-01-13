import XCTest
@testable import Atlas

final class StatsMetricEngineTests: XCTestCase {

    func testBaselineUsesPercentiles() throws {
        let calendar = DateRanges.isoCalendar()
        let now = Date()
        let start = DateRanges.startOfWeekMonday(for: now, calendar: calendar)
        let weeks = (0..<5).compactMap { offset in
            calendar.date(byAdding: .day, value: -7 * offset, to: start)
        }.reversed()

        let series: [WeeklyMetricValue] = zip(weeks, [10.0, 20.0, 30.0, 40.0, 50.0]).map {
            WeeklyMetricValue(weekStart: $0.0, value: $0.1)
        }

        let baseline = StatsBaselineEngine.baseline(series: series)
        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline?.floor ?? 0, 18, accuracy: 0.1)
        XCTAssertEqual(baseline?.band?.upperBound ?? 0, 42, accuracy: 0.1)
    }

    func testLaRT5ForPinnedLift() throws {
        let calendar = DateRanges.isoCalendar()
        let now = Date()
        let sessions = [
            session(weeksAgo: 0, calendar: calendar, sets: [
                ("Bench Press", 90, 6),
                ("Bench Press", 110, 5),
                ("Bench Press", 60, 12)
            ])
        ]

        let dashboard = StatsMetricEngine.computeDashboard(
            sessions: sessions,
            pinnedLifts: ["Bench Press"],
            mode: .strength,
            range: .sevenDays,
            filter: .keyLifts,
            preferredUnit: .kg,
            now: now,
            calendar: calendar
        )

        let card = dashboard.cards.first { $0.metric == .strengthCapacity }
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.rawValue ?? 0, 110, accuracy: 0.01)
    }

    func testJunkVolumeDetection() throws {
        let calendar = DateRanges.isoCalendar()
        let now = Date()
        let sessions = [
            session(weeksAgo: 3, calendar: calendar, sets: [("Bench", 100, 10)]),
            session(weeksAgo: 2, calendar: calendar, sets: [("Bench", 100, 12)]),
            session(weeksAgo: 1, calendar: calendar, sets: [("Bench", 105, 10)]),
            session(weeksAgo: 0, calendar: calendar, sets: [("Bench", 60, 10), ("Bench", 120, 10)])
        ]

        let summary = StatsMetricEngine.debugJunkSummary(sessions: sessions, range: .fourWeeks, now: now)
        XCTAssertEqual(summary.totalJunkSets, 1)
        XCTAssertEqual(summary.byExercise["Bench"], 1)
    }

    // MARK: - Helpers

    private func session(weeksAgo: Int, calendar: Calendar, sets: [(String, Double, Int)]) -> SessionData {
        let endOfWeek = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: Date()) ?? Date()
        var exerciseSets: [String: [SetData]] = [:]
        for (idx, entry) in sets.enumerated() {
            let created = calendar.date(byAdding: .minute, value: idx * 3, to: endOfWeek) ?? endOfWeek
            let set = SetData(tagRaw: SetTag.S.rawValue, weightKg: entry.1, reps: entry.2, createdAt: created)
            exerciseSets[entry.0, default: []].append(set)
        }

        let exercises = exerciseSets.enumerated().map { index, pair in
            ExerciseData(name: pair.key, orderIndex: index, sets: pair.value)
        }

        return SessionData(
            id: UUID(),
            startedAt: calendar.date(byAdding: .minute, value: -45, to: endOfWeek) ?? endOfWeek,
            endedAt: endOfWeek,
            isHidden: false,
            totalSets: sets.count,
            durationSeconds: 3600,
            exercises: exercises
        )
    }
}
