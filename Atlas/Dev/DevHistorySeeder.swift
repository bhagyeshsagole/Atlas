//
//  DevHistorySeeder.swift
//  Atlas
//
//  What this file is:
//  - DEBUG-only helper that seeds sample workout sessions for calendar/history testing.
//
//  Where it’s used:
//  - Can be called during development to populate SwiftData with fake sessions.
//
//  Called from:
//  - Intended to be triggered from app boot in DEBUG (e.g., `AtlasApp`) when you want seeded data.
//
//  Key concepts:
//  - Uses a UserDefaults flag to seed only once per install to avoid duplicate entries.
//
//  Safe to change:
//  - Seed dates, exercises, or counts for testing; keep inside `#if DEBUG`.
//
//  NOT safe to change:
//  - Running this in release builds; seeding real users would pollute their history.
//
//  Common bugs / gotchas:
//  - Forgetting to reset the UserDefaults key will prevent reseeding after changes.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Session History v1 — Pass 2
//

#if DEBUG
import Foundation
import SwiftData

enum DevHistorySeeder {
    private static let seedFlagKey = "DevHistorySeederJan2to4Seeded"

    static func seedIfNeeded(modelContext: ModelContext, historyStore: HistoryStore) {
        guard !UserDefaults.standard.bool(forKey: seedFlagKey) else { return }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        let seedDays: [(day: Int, title: String, exercises: [(String, Double, Int)])] = [
            (2, "Dev Seed — Push", [("Bench Press", 70, 8), ("Shoulder Press", 32, 10)]),
            (3, "Dev Seed — Pull", [("Pull-Up", 0, 8), ("Row", 55, 10)]),
            (4, "Dev Seed — Legs", [("Squat", 90, 8), ("RDL", 75, 10)])
        ]

        for seed in seedDays {
            guard let start = calendar.date(from: DateComponents(year: currentYear, month: 1, day: seed.day, hour: 9, minute: 0)) else { continue }
            let end = calendar.date(byAdding: .minute, value: 65, to: start) ?? start.addingTimeInterval(3600)

            let session = historyStore.startSession(routineId: nil, routineTitle: seed.title, exercises: seed.exercises.map { $0.0 })
            session.startedAt = start

            for (index, exercise) in seed.exercises.enumerated() {
                historyStore.addSet(session: session, exerciseName: exercise.0, orderIndex: index, tag: .S, weightKg: exercise.1, reps: exercise.2)
                historyStore.addSet(session: session, exerciseName: exercise.0, orderIndex: index, tag: .S, weightKg: exercise.1, reps: exercise.2 - 2)
            }

            _ = historyStore.endSession(session: session)
            session.endedAt = end
            try? modelContext.save()
        }

        UserDefaults.standard.set(true, forKey: seedFlagKey)
        #if DEBUG
        print("[DEV] Seeded history sessions for Jan 2-4 (year \(currentYear)).")
        #endif
    }
}
#endif
