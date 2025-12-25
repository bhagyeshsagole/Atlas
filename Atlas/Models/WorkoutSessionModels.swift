import Foundation
import SwiftData

@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var routineId: UUID?
    var routineTitle: String
    var startedAt: Date
    var endedAt: Date?
    var isCompleted: Bool
    @Relationship(deleteRule: .cascade) var exercises: [ExerciseLog]

    init(id: UUID = UUID(), routineId: UUID?, routineTitle: String, startedAt: Date = Date(), endedAt: Date? = nil, isCompleted: Bool = false, exercises: [ExerciseLog] = []) {
        self.id = id
        self.routineId = routineId
        self.routineTitle = routineTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isCompleted = isCompleted
        self.exercises = exercises
    }
}

@Model
final class ExerciseLog {
    @Attribute(.unique) var id: UUID
    var name: String
    var orderIndex: Int
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade) var sets: [SetLog]

    init(id: UUID = UUID(), name: String, orderIndex: Int, session: WorkoutSession? = nil, sets: [SetLog] = []) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.session = session
        self.sets = sets
    }
}

@Model
final class SetLog {
    @Attribute(.unique) var id: UUID
    var tag: String
    var weightKg: Double?
    var reps: Int
    var createdAt: Date
    var exercise: ExerciseLog?

    init(id: UUID = UUID(), tag: String, weightKg: Double?, reps: Int, createdAt: Date = Date(), exercise: ExerciseLog? = nil) {
        self.id = id
        self.tag = tag
        self.weightKg = weightKg
        self.reps = reps
        self.createdAt = createdAt
        self.exercise = exercise
    }
}

enum WorkoutUnits {
    case kg
    case lb

    init(from stored: String) {
        self = stored.lowercased() == "lb" ? .lb : .kg
    }
}

enum WorkoutSessionFormatter {
    static let kgToLb: Double = 2.20462

    static func kg(from value: Double, unit: WorkoutUnits) -> Double {
        switch unit {
        case .kg: return value
        case .lb: return value / kgToLb
        }
    }

    static func displayWeightStrings(weightKg: Double?, preferred: WorkoutUnits) -> (kg: String, lb: String) {
        guard let weightKg else { return ("Bodyweight", "Bodyweight") }
        let kgValue = weightKg
        let lbValue = weightKg * kgToLb
        return (String(format: "%.1f kg", kgValue), String(format: "%.1f lb", lbValue))
    }

    static func formatSetLine(set: SetLog, preferred: WorkoutUnits) -> String {
        let weights = displayWeightStrings(weightKg: set.weightKg, preferred: preferred)
        let primary = preferred == .kg ? weights.kg : weights.lb
        let secondary = preferred == .kg ? weights.lb : weights.kg
        return "\(primary) | \(secondary) × \(set.reps)"
    }

    /// VISUAL TWEAK: Keep formatting helpers in one place so we can tune the “Last Session” display style later.
    static func lastSessionLines(for exercise: ExerciseLog, preferred: WorkoutUnits) -> [String] {
        exercise.sets
            .sorted(by: { $0.createdAt < $1.createdAt })
            .enumerated()
            .map { index, set in
                let prefix = "S\(index + 1) — "
                return prefix + formatSetLine(set: set, preferred: preferred)
            }
    }
}

enum WorkoutSessionHistory {
    static func latestExerciseLog(
        for exerciseName: String,
        context: ModelContext
    ) -> ExerciseLog? {
        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.isCompleted == true },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let sessions = try? context.fetch(sessionDescriptor) else { return nil }
        for session in sessions {
            if let match = session.exercises.first(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
                return match
            }
        }
        return nil
    }
}
