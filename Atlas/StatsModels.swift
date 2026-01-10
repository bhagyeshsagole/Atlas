import Foundation

enum StatsLens: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case all = "All-time"

    var id: String { rawValue }
}

enum MuscleGroup: String, CaseIterable, Identifiable {
    case legs = "Legs"
    case back = "Back"
    case chest = "Chest"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case core = "Core"

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

struct BucketScore: Equatable {
    var score0to10: Int          // 0...10
    var progress01: Double       // 0.0...1.0
    var reasons: [String] = []
    var suggestions: [String] = []
}

extension BucketScore {
    var bucket: MuscleGroup { MuscleGroup.allCases.first ?? .legs }
    var score: Int { score0to10 }
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
            ($0, BucketScore(score0to10: 0, progress01: 0))
        })
        return StatsMetrics(
            lens: lens,
            muscle: emptyMuscle,
            workload: .zero,
            coach: .empty
        )
    }
}
