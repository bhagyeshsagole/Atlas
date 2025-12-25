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
    /// DEV MAP: Fake history seeding (DEBUG-only) lives here.
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
        let cal = Calendar.current

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // December 18, 2025 at 18:51 — Push Weight Training
        let stravaPush_2025_12_18 = cal.date(from: DateComponents(year: 2025, month: 12, day: 18, hour: 18, minute: 51)) ?? now

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // December 15, 2025 at 16:34 — Pull (Back + Biceps + Traps) Weight Training
        let stravaPull_2025_12_15 = cal.date(from: DateComponents(year: 2025, month: 12, day: 15, hour: 16, minute: 34)) ?? now

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // December 14, 2025 at 15:53 — Legs + Shoulders Weight Training
        let stravaLegsShoulders_2025_12_14 = cal.date(from: DateComponents(year: 2025, month: 12, day: 14, hour: 15, minute: 53)) ?? now

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // November 29, 2025 at 16:40 — Pull Weight Training
        let stravaPull_2025_11_29 = cal.date(from: DateComponents(year: 2025, month: 11, day: 29, hour: 16, minute: 40)) ?? now

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // November 28, 2025 at 15:21 — Push Weight Training
        let stravaPush_2025_11_28 = cal.date(from: DateComponents(year: 2025, month: 11, day: 28, hour: 15, minute: 21)) ?? now

        // strava history as data for (Bhagyesh Sagole — Apple Watch Series 9)
        // November 26, 2025 at 06:19 — Legs Weight Training
        let stravaLegs_2025_11_26 = cal.date(from: DateComponents(year: 2025, month: 11, day: 26, hour: 6, minute: 19)) ?? now

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
            ),

            // strava history as data for (December 18, 2025 at 18:51 — Push Weight Training)
            SeedSession(
                routineTitle: "Push Weight Training",
                date: stravaPush_2025_12_18,
                exercises: [
                    SeedExercise(
                        name: "Barbell Bench Press",
                        sets: [
                            SeedSet(order: 0, tag: "W", weightKg: 20.4, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 43.1, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 52.2, reps: 6),
                            SeedSet(order: 3, tag: "S", weightKg: 43.1, reps: 10),
                            SeedSet(order: 4, tag: "S", weightKg: 43.1, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Incline DB Press (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 15.9, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 15.9, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 15.9, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Pec Deck",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 31.8, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 40.8, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 45.4, reps: 12),
                            SeedSet(order: 3, tag: "S", weightKg: 52.2, reps: 14)
                        ]
                    ),
                    SeedExercise(
                        name: "Barbell Shoulder Press",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 29.5, reps: 6),
                            SeedSet(order: 2, tag: "S", weightKg: 24.9, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "DB Lateral Raise (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 6.8, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 6.8, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "DB Shrugs (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 31.8, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 31.8, reps: 12)
                        ]
                    ),
                    SeedExercise(
                        name: "Triceps Press Machine",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 59.0, reps: 16),
                            SeedSet(order: 1, tag: "S", weightKg: 68.0, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 68.0, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Single-Arm Cable Pushdown (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 4.5, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 4.5, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 4.5, reps: 12)
                        ]
                    ),
                    SeedExercise(
                        name: "Overhead Cable Extension",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 9.1, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 9.1, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 9.1, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Abs Machine",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 15),
                            SeedSet(order: 1, tag: "S", weightKg: 31.8, reps: 10)
                        ]
                    )
                ]
            ),

            // strava history as data for (December 15, 2025 at 16:34 — Pull (Back + Biceps + Traps) Weight Training)
            SeedSession(
                routineTitle: "Pull (Back + Biceps + Traps) Weight Training",
                date: stravaPull_2025_12_15,
                exercises: [
                    SeedExercise(
                        name: "Chest-Supported Row (machine)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 63.5, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 63.5, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 63.5, reps: 6)
                        ]
                    ),
                    SeedExercise(
                        name: "Wide-Grip Lat Pulldown",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 45.4, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 45.4, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 38.6, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Seated Cable Row (neutral/close grip)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 45.4, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 52.2, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 52.2, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Straight-Arm Cable Pulldown",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 14.7, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 14.7, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 14.7, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Shrug machine",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 81.6, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 81.6, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Seated Concentration Curls (each)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 9.1, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 9.1, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 9.1, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Hammer Curls (each)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 11.3, reps: 8),
                            SeedSet(order: 1, tag: "S", weightKg: 11.3, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 11.3, reps: 6)
                        ]
                    )
                ]
            ),

            // strava history as data for (December 14, 2025 at 15:53 — Legs + Shoulders Weight Training)
            SeedSession(
                routineTitle: "Legs + Shoulders Weight Training",
                date: stravaLegsShoulders_2025_12_14,
                exercises: [
                    SeedExercise(
                        name: "Hack Squat",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 40.8, reps: 8),
                            SeedSet(order: 1, tag: "S", weightKg: 81.6, reps: 6),
                            SeedSet(order: 2, tag: "S", weightKg: 68.0, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Leg Press",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 90.7, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 90.7, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 90.7, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Romanian Deadlift",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 22.7, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 27.2, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 27.2, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Iso-Lateral Kneeling Hamstring Curl (each leg)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 11.3, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 11.3, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 11.3, reps: 12)
                        ]
                    ),
                    SeedExercise(
                        name: "Standing Calf Raise",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 63.5, reps: 20),
                            SeedSet(order: 1, tag: "S", weightKg: 81.6, reps: 20),
                            SeedSet(order: 2, tag: "S", weightKg: 81.6, reps: 22)
                        ]
                    ),
                    SeedExercise(
                        name: "Barbell Shoulder Press",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 16),
                            SeedSet(order: 1, tag: "S", weightKg: 24.9, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 24.9, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "DB Lateral Raise (each)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 15),
                            SeedSet(order: 1, tag: "S", weightKg: 4.5, reps: 15),
                            SeedSet(order: 2, tag: "S", weightKg: 4.5, reps: 15)
                        ]
                    ),
                    SeedExercise(
                        name: "Rear Delts (machine)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 22.7, reps: 20),
                            SeedSet(order: 1, tag: "S", weightKg: 27.2, reps: 15),
                            SeedSet(order: 2, tag: "S", weightKg: 27.2, reps: 15)
                        ]
                    ),

                    // Extras (not in volume total)
                    SeedExercise(
                        name: "Tibialis Raises",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: nil, reps: 14),   // BW × 14
                            SeedSet(order: 1, tag: "S", weightKg: 4.5, reps: 15),   // 10 lb × 15
                            SeedSet(order: 2, tag: "S", weightKg: 9.1, reps: 18)    // 20 lb × 18
                        ]
                    )
                ]
            ),

            // strava history as data for (November 29, 2025 at 16:40 — Pull Weight Training)
            SeedSession(
                routineTitle: "Pull Weight Training",
                date: stravaPull_2025_11_29,
                exercises: [
                    SeedExercise(
                        name: "Pull-ups (assisted; effective load)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 61.9, reps: 5),
                            SeedSet(order: 1, tag: "S", weightKg: 57.3, reps: 5)
                        ]
                    ),
                    SeedExercise(
                        name: "Chest-Supported Row (machine)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 63.5, reps: 9),
                            SeedSet(order: 1, tag: "S", weightKg: 68.0, reps: 6),
                            SeedSet(order: 2, tag: "S", weightKg: 68.0, reps: 9),
                            SeedSet(order: 3, tag: "DS", weightKg: 45.4, reps: 6) // drop (not in volume total)
                        ]
                    ),
                    SeedExercise(
                        name: "Seated Cable Row — neutral",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 59.0, reps: 6),
                            SeedSet(order: 1, tag: "S", weightKg: 52.2, reps: 7),
                            SeedSet(order: 2, tag: "S", weightKg: 45.4, reps: 6)
                        ]
                    ),
                    SeedExercise(
                        name: "Wide-Grip Lat Pulldown",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 45.4, reps: 8),
                            SeedSet(order: 1, tag: "S", weightKg: 38.6, reps: 13),
                            SeedSet(order: 2, tag: "S", weightKg: 38.6, reps: 12)
                        ]
                    ),
                    SeedExercise(
                        name: "Straight-Arm Cable Pulldown",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 10.2, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 14.7, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 14.7, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Seated Concentration Curl (each arm)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 6.8, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 6.8, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Hammer Curl (DB, standing) (each)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 9.1, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 11.3, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 9.1, reps: 8)
                        ]
                    )
                ]
            ),

            // strava history as data for (November 28, 2025 at 15:21 — Push Weight Training)
            SeedSession(
                routineTitle: "Push Weight Training",
                date: stravaPush_2025_11_28,
                exercises: [
                    SeedExercise(
                        name: "Barbell Chest Press",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 43.1, reps: 11),
                            SeedSet(order: 1, tag: "S", weightKg: 43.1, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 43.1, reps: 8),
                            SeedSet(order: 3, tag: "S", weightKg: 43.1, reps: 6)
                        ]
                    ),
                    SeedExercise(
                        name: "Incline Dumbbell Press (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 18.1, reps: 8),
                            SeedSet(order: 1, tag: "S", weightKg: 18.1, reps: 8),
                            SeedSet(order: 2, tag: "S", weightKg: 18.1, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Pec Deck",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 45.4, reps: 6),
                            SeedSet(order: 1, tag: "S", weightKg: 40.8, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 40.8, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Seated Barbell Shoulder Press",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 20.4, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 20.4, reps: 10),
                            SeedSet(order: 3, tag: "S", weightKg: 20.4, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "DB Lateral Raise (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 4.5, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 4.5, reps: 14)
                        ]
                    ),
                    SeedExercise(
                        name: "Reverse Pec Deck",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 22.7, reps: 14),
                            SeedSet(order: 1, tag: "S", weightKg: 22.7, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 22.7, reps: 8),
                            SeedSet(order: 3, tag: "S", weightKg: 13.6, reps: 5)
                        ]
                    ),
                    SeedExercise(
                        name: "Triceps Press Machine",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 68.0, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 68.0, reps: 7),
                            SeedSet(order: 2, tag: "S", weightKg: 59.0, reps: 8),
                            SeedSet(order: 3, tag: "S", weightKg: 40.8, reps: 5)
                        ]
                    ),
                    SeedExercise(
                        name: "Single-Arm Cable Pushdown (per arm)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 12),
                            SeedSet(order: 1, tag: "S", weightKg: 6.8, reps: 6),
                            SeedSet(order: 2, tag: "S", weightKg: 4.5, reps: 10),
                            SeedSet(order: 3, tag: "S", weightKg: 3.4, reps: 6)
                        ]
                    ),
                    SeedExercise(
                        name: "Overhead Cable Extension",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 15),
                            SeedSet(order: 1, tag: "S", weightKg: 6.8, reps: 15),
                            SeedSet(order: 2, tag: "S", weightKg: 6.8, reps: 15)
                        ]
                    ),
                    SeedExercise(
                        name: "DB Wrist Curls (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 6.8, reps: 24),
                            SeedSet(order: 1, tag: "S", weightKg: 6.8, reps: 15),
                            SeedSet(order: 2, tag: "S", weightKg: 6.8, reps: 15)
                        ]
                    ),
                    SeedExercise(
                        name: "Reverse Wrist Curls (each hand)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 4.5, reps: 10)
                        ]
                    ),

                    // Extras (not in volume total)
                    // Note: reps here represent seconds for carries.
                    SeedExercise(
                        name: "Farmer’s Carry (seconds)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 30),
                            SeedSet(order: 1, tag: "S", weightKg: 20.4, reps: 30)
                        ]
                    )
                ]
            ),

            // strava history as data for (November 26, 2025 at 06:19 — Legs Weight Training)
            SeedSession(
                routineTitle: "Legs Weight Training",
                date: stravaLegs_2025_11_26,
                exercises: [
                    SeedExercise(
                        name: "Hack Squat",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 40.8, reps: 10),
                            SeedSet(order: 1, tag: "S", weightKg: 63.5, reps: 6),
                            SeedSet(order: 2, tag: "S", weightKg: 40.8, reps: 8),
                            SeedSet(order: 3, tag: "S", weightKg: 40.8, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Romanian Deadlift",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 20.4, reps: 8),
                            SeedSet(order: 1, tag: "S", weightKg: 20.4, reps: 10)
                        ]
                    ),
                    SeedExercise(
                        name: "Iso-Lateral Kneeling Hamstring Curl (each leg)",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 11.3, reps: 16),
                            SeedSet(order: 1, tag: "S", weightKg: 11.3, reps: 10),
                            SeedSet(order: 2, tag: "S", weightKg: 11.3, reps: 8)
                        ]
                    ),
                    SeedExercise(
                        name: "Standing Calf Raise",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: 40.8, reps: 15),
                            SeedSet(order: 1, tag: "S", weightKg: 72.6, reps: 12),
                            SeedSet(order: 2, tag: "S", weightKg: 72.6, reps: 12)
                        ]
                    ),

                    // Extras (not in volume total)
                    SeedExercise(
                        name: "Tibialis Raises",
                        sets: [
                            SeedSet(order: 0, tag: "S", weightKg: nil, reps: 20),  // BW × 20
                            SeedSet(order: 1, tag: "S", weightKg: 4.5, reps: 20)   // 10 lb × 20
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
