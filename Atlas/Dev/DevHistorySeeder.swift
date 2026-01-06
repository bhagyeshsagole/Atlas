//
//  DevHistorySeeder.swift
//  Atlas
//
//  DEBUG-only helper to seed backdated workout sessions for testing calendar/history flows.
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
