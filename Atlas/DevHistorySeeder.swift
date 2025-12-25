import Foundation
import SwiftData

#if DEBUG
struct DevFlags {
    /// DEV SEED: Toggle `DevFlags.seedHistory` to true to insert fake sessions.
    static var seedHistory: Bool = false
}

/// DEV SEED: Toggle `DevFlags.seedHistory` to true to insert fake sessions.
/// DEV SEED: Edit `sampleSessions` below to change dates/weights/reps.
/// DEV SEED: Expected format:
///   Session(date: ..., routineTitle: "...", exercises: [
///     Exercise(name: "...", sets: [
///       Set(tag: .warmup, weightKg: 20, reps: 10),
///       Set(tag: .set,    weightKg: 40, reps: 8),
///       Set(tag: .dropset,weightKg: 30, reps: 12)
///     ])
///   ])
enum DevHistorySeeder {
    private static let seededKey = "dev_seed_history_v1"

    static func seedIfNeeded(modelContext: ModelContext) {
        guard DevFlags.seedHistory else { return }
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let sessions = sampleSessions()
        for session in sessions {
            let sessionModel = WorkoutSession(
                id: session.id,
                routineId: session.routineId,
                routineTitle: session.routineTitle,
                startedAt: session.date,
                endedAt: session.date.addingTimeInterval(45 * 60),
                isCompleted: true
            )
            for (index, exercise) in session.exercises.enumerated() {
                let exerciseLog = ExerciseLog(
                    id: UUID(),
                    name: exercise.name,
                    orderIndex: index,
                    session: sessionModel
                )
                for set in exercise.sets {
                    let setLog = SetLog(
                        id: UUID(),
                        tag: set.tag,
                        weightKg: set.weightKg,
                        reps: set.reps,
                        createdAt: session.date.addingTimeInterval(Double(set.order) * 60),
                        exercise: exerciseLog
                    )
                    exerciseLog.sets.append(setLog)
                }
                sessionModel.exercises.append(exerciseLog)
            }
            modelContext.insert(sessionModel)
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    private static func sampleSessions() -> [SeedSession] {
        // DEV SEED: Edit sample sessions here. Use past dates and vary weights/reps/tags.
        let now = Date()
        return [
            SeedSession(
                routineTitle: "Dev Push",
                date: Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now,
                exercises: [
                    SeedExercise(
                        name: "Bench Press",
                        sets: [
                            SeedSet(order: 0, tag: "W", weightKg: 40, reps: 10), // DEV SEED: adjust weightKg/reps/tag
                            SeedSet(order: 1, tag: "S", weightKg: 60, reps: 8),
                            SeedSet(order: 2, tag: "DS", weightKg: 50, reps: 12)
                        ]
                    ),
                    SeedExercise(
                        name: "Overhead Press",
                        sets: [
                            SeedSet(order: 0, tag: "W", weightKg: 20, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 35, reps: 10)
                        ]
                    )
                ]
            ),
            SeedSession(
                routineTitle: "Dev Pull",
                date: Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now,
                exercises: [
                    SeedExercise(
                        name: "Lat Pulldown",
                        sets: [
                            SeedSet(order: 0, tag: "W", weightKg: 25, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 45, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 45, reps: 9)
                        ]
                    ),
                    SeedExercise(
                        name: "Barbell Row",
                        sets: [
                            SeedSet(order: 0, tag: "W", weightKg: 30, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 55, reps: 8)
                        ]
                    )
                ]
            )
        ]
    }

    private struct SeedSession {
        let id: UUID = UUID()
        let routineId: UUID? = nil
        let routineTitle: String
        let date: Date
        let exercises: [SeedExercise]
    }

    private struct SeedExercise {
        let name: String
        let orderIndex: Int
        let sets: [SeedSet]

        init(name: String, sets: [SeedSet]) {
            self.name = name
            self.sets = sets
            self.orderIndex = 0
        }
    }

    private struct SeedSet {
        let order: Int
        let tag: String
        let weightKg: Double?
        let reps: Int
    }
}
#endif
