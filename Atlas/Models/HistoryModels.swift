//
//  HistoryModels.swift
//  Atlas
//
//  What this file is:
//  - SwiftData models for stored workout sessions, exercises, and sets.
//
//  Where it’s used:
//  - Persisted by `HistoryStore` and queried across HomeView and history screens.
//  - Shapes the schema of the on-device history database.
//
//  Called from:
//  - Referenced in `AtlasApp.modelTypes`, `HistoryStore`, `WorkoutSessionView`, `AllHistoryView`, `DayHistoryView`, and `PostWorkoutSummaryView`.
//
//  Key concepts:
//  - `@Model` marks types that SwiftData persists automatically.
//  - `@Relationship(deleteRule: .cascade)` means deleting a session also deletes its exercises/sets.
//
//  Safe to change:
//  - Add optional fields for new stats (with defaults) while handling migrations.
//
//  NOT safe to change:
//  - Removing properties or changing types without migration; users could lose stored history.
//  - Unique identifiers (`@Attribute(.unique)`) which keep rows from duplicating.
//
//  Common bugs / gotchas:
//  - Storing weights in lb will skew volume; weights are stored in kg and converted for display.
//  - Changing tag values without updating `SetTag` will desync tag handling in the UI.
//
//  DEV MAP:
//  - See: DEV_MAP.md → C) Workout Sessions / History (real performance logs)
//
// FLOW SUMMARY:
// WorkoutSession holds exercises → ExerciseLog holds sets → SetLog stores weight/reps; HistoryStore reads/writes these models via SwiftData.
//

import Foundation
import SwiftData

/// DEV MAP: SwiftData history (performed sessions) lives here.
/// DEV NOTE: Weight is stored in KG; convert to LB only for UI.
/// VISUAL TWEAK: If we ever change tags beyond W/S/DS, update SetTag here.
@Model
final class WorkoutSession {
    @Attribute(.unique) var id: UUID
    var routineId: UUID?
    var routineTemplateId: UUID?
    var routineTitle: String
    var startedAt: Date
    var endedAt: Date?
    var totalSets: Int
    var totalReps: Int
    var volumeKg: Double
    var aiPostSummaryText: String
    var aiPostSummaryJSON: String
    var rating: Double?
    /// Compatibility: existing flows track completion/duration; keep them for now.
    var isCompleted: Bool
    var isHidden: Bool = false
    var durationSeconds: Int?
    var aiPostSummaryGeneratedAt: Date?
    var aiPostSummaryModel: String?
    @Relationship(deleteRule: .cascade) var exercises: [ExerciseLog]

    init(
        id: UUID = UUID(),
        routineId: UUID?,
        routineTemplateId: UUID? = nil,
        routineTitle: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        totalSets: Int = 0,
        totalReps: Int = 0,
        volumeKg: Double = 0,
        aiPostSummaryText: String = "",
        aiPostSummaryJSON: String = "",
        rating: Double? = nil,
        isCompleted: Bool = false,
        isHidden: Bool = false,
        durationSeconds: Int? = nil,
        aiPostSummaryGeneratedAt: Date? = nil,
        aiPostSummaryModel: String? = nil,
        exercises: [ExerciseLog] = []
    ) {
        self.id = id
        self.routineId = routineId
        self.routineTemplateId = routineTemplateId
        self.routineTitle = routineTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.volumeKg = volumeKg
        self.aiPostSummaryText = aiPostSummaryText
        self.aiPostSummaryJSON = aiPostSummaryJSON
        self.rating = rating
        self.isCompleted = isCompleted
        self.isHidden = isHidden
        self.durationSeconds = durationSeconds
        self.aiPostSummaryGeneratedAt = aiPostSummaryGeneratedAt
        self.aiPostSummaryModel = aiPostSummaryModel
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

    init(
        id: UUID = UUID(),
        name: String,
        orderIndex: Int,
        session: WorkoutSession? = nil,
        sets: [SetLog] = []
    ) {
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
    var tagRaw: String
    var weightKg: Double?
    var reps: Int
    /// Captures the unit the user used when entering this set (for display).
    var enteredUnitRaw: String = "kg"
    var createdAt: Date
    var exercise: ExerciseLog?

    init(
        id: UUID = UUID(),
        tag: String,
        weightKg: Double?,
        reps: Int,
        enteredUnit: WorkoutUnits = .kg,
        createdAt: Date = Date(),
        exercise: ExerciseLog? = nil
    ) {
        self.id = id
        self.tagRaw = tag
        self.weightKg = weightKg
        self.reps = reps
        self.enteredUnitRaw = enteredUnit == .lb ? "lb" : "kg"
        self.createdAt = createdAt
        self.exercise = exercise
    }

    /// Compatibility alias so existing code that references `.tag` continues to compile.
    var tag: String {
        get { tagRaw }
        set { tagRaw = newValue }
    }

    var enteredUnit: WorkoutUnits {
        get { WorkoutUnits(from: enteredUnitRaw) }
        set { enteredUnitRaw = newValue == .lb ? "lb" : "kg" }
    }
}

enum SetTag: String {
    case W
    case S
    case DS
}

extension SetTag {
    var displayName: String {
        switch self {
        case .W: return "Warmup"
        case .S: return "Standard"
        case .DS: return "Drop"
        }
    }
}

enum WorkoutUnits {
    case kg
    case lb

    init(from stored: String) {
        self = stored.lowercased() == "lb" ? .lb : .kg
    }

    var label: String {
        switch self {
        case .kg: return "kg"
        case .lb: return "lb"
        }
    }
}

enum WorkoutSessionFormatter {
    static let kgToLb: Double = 2.20462

    static func volumeString(volumeKg: Double, unit: WorkoutUnits) -> String {
        guard volumeKg > 0 else { return "—" }
        let value = unit == .kg ? volumeKg : volumeKg * kgToLb
        let unitLabel = unit == .kg ? "kg" : "lb"
        return String(format: "%.0f \(unitLabel)", value)
    }

    static func kg(from value: Double, unit: WorkoutUnits) -> Double {
        switch unit {
        case .kg: return value
        case .lb: return value / kgToLb
        }
    }

    static func formatSetLine(set: SetLog, preferred: WorkoutUnits) -> String {
        let weightText = WeightFormatter.format(set.weightKg, unit: preferred)
        return "\(weightText) × \(set.reps)"
    }

    /// VISUAL TWEAK: Keep formatting helpers in one place so we can tune the “Last Session” display style later.
    static func lastSessionLines(for exercise: ExerciseLog, preferred: WorkoutUnits) -> [String] {
        exercise.sets
            .sorted(by: { $0.createdAt < $1.createdAt })
            .enumerated()
            .map { index, set in
                let prefix = tagLabel(for: set, index: index)
                return "\(prefix) — " + formatSetLine(set: set, preferred: preferred)
            }
    }

    private static func tagLabel(for set: SetLog, index: Int) -> String {
        switch SetTag(rawValue: set.tag) {
        case .W:
            return "Warm-up"
        case .S:
            return "Standard"
        case .DS:
            return "Drop set"
        case .none:
            return "Set \(index + 1)"
        }
    }
}

enum WorkoutSessionHistory {
    static func latestCompletedExerciseLog(
        for exerciseName: String,
        excluding sessionId: UUID? = nil,
        context: ModelContext
    ) -> ExerciseLog? {
        let descriptor = FetchDescriptor<WorkoutSession>()
        guard let sessions = try? context.fetch(descriptor) else { return nil }
        let filtered = sessions
            .filter { session in
                if let exclude = sessionId, session.id == exclude { return false }
                guard session.isHidden == false else { return false }
                guard let ended = session.endedAt, ended <= Date() else { return false }
                return session.totalSets > 0
            }
            .sorted { (lhs, rhs) in
                (lhs.endedAt ?? lhs.startedAt) > (rhs.endedAt ?? rhs.startedAt)
            }

        for session in filtered {
            if let match = session.exercises.first(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
                return match
            }
        }
        return nil
    }

    static func guidanceRange(from lastLog: ExerciseLog, displayUnit: WorkoutUnits) -> String {
        let sets = lastLog.sets.sorted(by: { $0.createdAt < $1.createdAt })
        guard let top = sets.max(by: { lhs, rhs in
            let l = (lhs.weightKg ?? 0) * Double(max(lhs.reps, 1))
            let r = (rhs.weightKg ?? 0) * Double(max(rhs.reps, 1))
            return l < r
        }) else {
            return "Warmup: 2 sets · 8–12 reps\nWorking: 3–4 sets · 6–10 reps"
        }

        let baseWeightKg = top.weightKg ?? 0
        let warmupLow = max(baseWeightKg * 0.4, baseWeightKg - 5)
        let warmupHigh = max(baseWeightKg * 0.6, warmupLow + 0.5)
        let workLow = max(baseWeightKg * 0.9, baseWeightKg - 2.5)
        let workHigh = max(baseWeightKg * 1.05, workLow + 0.5)

        let reps = max(top.reps, 1)
        let repLow = max(reps - 2, 1)
        let repHigh = reps + 2

        let warmupText = "\(WeightFormatter.format(warmupLow, unit: displayUnit))–\(WeightFormatter.format(warmupHigh, unit: displayUnit))"
        let workText = "\(WeightFormatter.format(workLow, unit: displayUnit))–\(WeightFormatter.format(workHigh, unit: displayUnit))"

        return "Warmup: \(warmupText) × \(repLow)–\(repHigh) reps\nWorking: \(workText) × \(repLow)–\(repHigh) reps"
    }
}
