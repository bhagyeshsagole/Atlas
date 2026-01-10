import Foundation

enum StatsLens: String, CaseIterable, Identifiable, Codable, Hashable {
    case week = "Week"
    case month = "Month"
    case all = "All-time"

    var id: String { rawValue }
}

/// Back-compat alias so older code that referenced StatsRange continues to work.
typealias StatsRange = StatsLens

enum MuscleGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case legs = "Legs"
    case back = "Back"
    case chest = "Chest"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"

    var id: String { rawValue }
}

enum MovementTag: String, CaseIterable, Codable, Hashable, Identifiable {
    case horizontalPress, inclinePress, flyAdduction, dipPattern
    case verticalPull, horizontalRow, rearDeltUpperBack, scapControl
    case kneeDominant, hinge, singleLeg, calves, gluteIso
    case overheadPress, lateralRaise, rearDeltER
    case bicepsCurl, tricepsExtension, forearmGrip
    case antiExtension, antiRotation, flexion, carry

    var id: String { rawValue }
}

// Back-compat for older StatsView code.
typealias MuscleBucket = MuscleGroup

extension MuscleGroup {
    var displayName: String {
        switch self {
        case .legs: return "Legs"
        case .back: return "Back"
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        }
    }
}

struct BucketScore: Equatable, Identifiable {
    var id: String { bucket.id }
    var bucket: MuscleGroup
    var score0to10: Int          // 0...10
    var progress01: Double       // 0.0...1.0
    var coveredTags: [MovementTag]
    var missingTags: [MovementTag]
    var hardSets: Int
    var trainingDays: Int
    var reasons: [String] = []
    var suggestions: [String] = []
}

extension Int {
    /// Clamp into the 0...10 score band.
    var score0to10: Int { Swift.max(0, Swift.min(10, self)) }
    var score0to10Double: Double { Double(score0to10) }
    var progress0to1: Double { Double(score0to10) / 10.0 }
}

struct WorkloadSummary: Equatable {
    var volume: Double
    var sets: Int
    var reps: Int

    static let zero = WorkloadSummary(volume: 0, sets: 0, reps: 0)
}

struct CoachSummary: Equatable {
    var streakWeeks: Int
    var next: String
    var reason: String

    static let empty = CoachSummary(streakWeeks: 0, next: "—", reason: "")
}

struct StatsMetrics: Equatable {
    var lens: StatsLens
    var muscle: [MuscleGroup: BucketScore]
    var workload: WorkloadSummary
    var coach: CoachSummary

    static func empty(_ lens: StatsLens) -> StatsMetrics {
        let emptyMuscle = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map {
            ($0, BucketScore(bucket: $0, score0to10: 0, progress01: 0, coveredTags: [], missingTags: [], hardSets: 0, trainingDays: 0))
        })
        return StatsMetrics(
            lens: lens,
            muscle: emptyMuscle,
            workload: .zero,
            coach: .empty
        )
    }
}
