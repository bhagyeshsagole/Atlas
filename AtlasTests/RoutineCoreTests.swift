//
//  RoutineCoreTests.swift
//  AtlasTests
//
//  Update: Hardening tests for parsing, constraints, and store roundtrips.
//

import XCTest
@testable import Atlas

final class RoutineCoreTests: XCTestCase {
    @MainActor
    func testExplicitListParsingUsesLocalHeuristics() async throws {
        let input = "lat row x 3 10-12 and shoulder press x 3 10-12"
        let workouts = try await RoutineAIService.parseWorkouts(from: input, routineTitleHint: "Test")
        XCTAssertEqual(workouts.count, 2)
    }

    @MainActor
    func testNormalizationHandlesCommasAndNewlines() async throws {
        let input = "apple lift x3 8-12, row x3 10-12\nface move x3 15"
        let workouts = try await RoutineAIService.parseWorkouts(from: input, routineTitleHint: "Test")
        XCTAssertEqual(workouts.count, 3)
    }

    func testExtractConstraints() {
        let constraints = RoutineAIService.extractConstraints(from: "at home no gym no dumbbells push day")
        XCTAssertTrue(constraints.atHome)
        XCTAssertTrue(constraints.noGym)
        XCTAssertTrue(constraints.noDumbbells)
        XCTAssertFalse(constraints.noMachines)
        XCTAssertEqual(constraints.preferredSplit, .push)
    }

    func testRoutineOverviewTruncationGuardrail() {
        let routine = Routine(
            id: UUID(),
            name: String(repeating: "Long Name ", count: 6),
            createdAt: Date(),
            workouts: (0..<8).map { _ in
                RoutineWorkout(id: UUID(), name: "Move", wtsText: "wts", repsText: "10-12")
            }
        )
        let text = routineOverviewText(routine)
        XCTAssertLessThan(text.count, 120)
    }

    @MainActor
    func testRoutineStoreRoundTripAddUpdateDelete() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RoutineStoreTests-\(UUID().uuidString).json")
        let store = RoutineStore(storageURL: tempURL)
        let routine = Routine(id: UUID(), name: "Test Routine", createdAt: Date(), workouts: [])

        store.addRoutine(routine)
        XCTAssertEqual(store.routines.count, 1)

        var updated = routine
        updated.name = "Updated Routine"
        store.updateRoutine(updated)
        XCTAssertEqual(store.routines.first?.name, "Updated Routine")

        store.save()

        let reloadedStore = RoutineStore(storageURL: tempURL)
        reloadedStore.load()
        XCTAssertEqual(reloadedStore.routines.count, 1)

        reloadedStore.deleteRoutine(id: updated.id)
        XCTAssertEqual(reloadedStore.routines.count, 0)
    }

    func testRoutineStoreLoadCorruptedFileDoesNotCrash() {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RoutineStoreCorrupted-\(UUID().uuidString).json")
        try? "not-json".data(using: .utf8)?.write(to: tempURL)
        let store = RoutineStore(storageURL: tempURL)
        store.load()
        XCTAssertTrue(store.routines.isEmpty)
    }
}
