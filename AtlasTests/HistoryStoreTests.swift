// Tests for HistoryStore session lifecycle and totals to guard regressions without adding new features.
import XCTest
import SwiftData
@testable import Atlas

final class HistoryStoreTests: XCTestCase {

    @MainActor
    func testEndSessionDiscardsWhenNoSets() throws {
        let (store, context) = makeStore()
        let session = store.startSession(routineId: nil, routineTitle: "Test", exercises: [])
        let stored = store.endSession(session: session)
        XCTAssertFalse(stored)
        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertTrue(fetched.isEmpty)
    }

    @MainActor
    func testTotalsComputedOnEnd() throws {
        let (store, _) = makeStore()
        let session = store.startSession(routineId: nil, routineTitle: "Totals", exercises: ["Bench"])
        store.addSet(session: session, exerciseName: "Bench", orderIndex: 0, tag: .S, weightKg: 50, reps: 5)
        store.addSet(session: session, exerciseName: "Bench", orderIndex: 0, tag: .S, weightKg: 60, reps: 3)
        let stored = store.endSession(session: session)
        XCTAssertTrue(stored)
        XCTAssertEqual(session.totalSets, 2)
        XCTAssertEqual(session.totalReps, 8)
        XCTAssertEqual(session.volumeKg, 50 * 5 + 60 * 3, accuracy: 0.001)
        XCTAssertNotNil(session.endedAt)
    }

    @MainActor
    func testStartSessionDedupesActiveDraft() throws {
        let (store, context) = makeStore()
        let first = store.startSession(routineId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"), routineTitle: "Dupes", exercises: [])
        let second = store.startSession(routineId: first.routineId, routineTitle: "Dupes", exercises: [])
        XCTAssertEqual(first.id, second.id)
        let fetched = try context.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(fetched.count, 1)
    }

    @MainActor
    func testLatestCompletedExerciseLogExcludesActiveSession() throws {
        let (store, context) = makeStore()
        let ended = store.startSession(routineId: nil, routineTitle: "Bench Day", exercises: ["Bench"])
        store.addSet(session: ended, exerciseName: "Bench", orderIndex: 0, tag: .S, weightKg: 80, reps: 8)
        XCTAssertTrue(store.endSession(session: ended))

        let active = store.startSession(routineId: nil, routineTitle: "Bench Draft", exercises: ["Bench"])
        store.addSet(session: active, exerciseName: "Bench", orderIndex: 0, tag: .S, weightKg: 60, reps: 5)

        let latest = WorkoutSessionHistory.latestCompletedExerciseLog(for: "Bench", excluding: active.id, context: context)
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.session?.id, ended.id)
    }

    @MainActor
    func testGuidanceRangeUsesLastEndedSession() throws {
        let (_, _) = makeStore()

        // Build a manual ExerciseLog with a strong top set.
        let session = WorkoutSession(routineId: nil, routineTemplateId: nil, routineTitle: "Test", startedAt: Date(), endedAt: Date(), totalSets: 0, totalReps: 0, volumeKg: 0, aiPostSummaryText: "", aiPostSummaryJSON: "", rating: nil, isCompleted: true, isHidden: false, durationSeconds: nil, aiPostSummaryGeneratedAt: nil, aiPostSummaryModel: nil, exercises: [])
        let exercise = ExerciseLog(name: "Bench", orderIndex: 0, session: session, sets: [])
        let topSet = SetLog(tag: SetTag.S.rawValue, weightKg: 100, reps: 8, enteredUnit: .kg, exercise: exercise)
        exercise.sets.append(topSet)
        session.exercises.append(exercise)

        let guidance = WorkoutSessionHistory.guidanceRange(from: exercise, displayUnit: .kg)
        XCTAssertTrue(guidance.contains("Warmup"))
        XCTAssertTrue(guidance.contains("Working"))
        XCTAssertTrue(guidance.contains("kg"))
    }

    @MainActor
    private func makeStore() -> (HistoryStore, ModelContext) {
        let schema = Schema([WorkoutSession.self, ExerciseLog.self, SetLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        return (HistoryStore(modelContext: context), context)
    }
}
