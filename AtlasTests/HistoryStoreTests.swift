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
    private func makeStore() -> (HistoryStore, ModelContext) {
        let schema = Schema([WorkoutSession.self, ExerciseLog.self, SetLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        return (HistoryStore(modelContext: context), context)
    }
}
