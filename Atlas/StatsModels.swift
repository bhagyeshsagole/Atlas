import Foundation

// MARK: - New Stats models

enum StatsExerciseFilter: String, CaseIterable, Identifiable {
    case allExercises
    case keyLifts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allExercises: return "All exercises"
        case .keyLifts: return "Key lifts"
        }
    }
}

enum TrendDirection {
    case up
    case down
    case flat
}

enum BaselineType {
    case auto
    case user
    case `default`
}

struct BaselineResult {
    let floor: Double
    let band: ClosedRange<Double>?
    let type: BaselineType
    let streakWeeks: Int
    let deltaPercent: Double

    var statusText: String {
        if floor <= 0 { return "No baseline yet" }
        let percentText = Self.percentFormatter.string(from: NSNumber(value: deltaPercent)) ?? "0%"
        if deltaPercent >= 0 {
            return "Cleared minimum by \(percentText)"
        } else {
            let cleanedPercent = percentText.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            return "Below minimum by \(cleanedPercent)"
        }
    }

    static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

enum StatsMetricKind: String, CaseIterable, Identifiable {
    case strengthCapacity
    case topSetOutput
    case overloadEvents
    case restDiscipline
    case hardSets
    case weeklyVolume
    case coverage
    case variety
    case density
    case hypertrophyDose
    case balance
    case workload
    case progressEvents
    case efficiency
    case recovery
    case monotony
    case junkVolume

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strengthCapacity: return "Strength Capacity"
        case .topSetOutput: return "Top Set Output"
        case .overloadEvents: return "Overload Events"
        case .restDiscipline: return "Rest Discipline"
        case .hardSets: return "Hard Sets"
        case .weeklyVolume: return "Weekly Volume Load"
        case .coverage: return "Coverage"
        case .variety: return "Exercise Variety"
        case .density: return "Work Capacity"
        case .hypertrophyDose: return "Hypertrophy Dose"
        case .balance: return "Balance"
        case .workload: return "Workload"
        case .progressEvents: return "Progress Events"
        case .efficiency: return "Efficiency"
        case .recovery: return "Recovery"
        case .monotony: return "Monotony"
        case .junkVolume: return "Junk Volume"
        }
    }
}

struct TrendCardModel: Identifiable {
    var id: StatsMetricKind { metric }
    let metric: StatsMetricKind
    let title: String
    let primaryValue: String
    let rawValue: Double
    let direction: TrendDirection
    let comparisonText: String
    let streakText: String
    let context: String?
}

struct WeeklyMetricValue: Identifiable, Equatable {
    var id: Date { weekStart }
    let weekStart: Date
    let value: Double
}

struct MinimumStripMetric: Identifiable {
    var id: StatsMetricKind { metric }
    let metric: StatsMetricKind
    let title: String
    let weekly: [WeeklyMetricValue]
    let baseline: BaselineResult?
}

struct BreakdownItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let valueText: String
    let detail: String?
}

struct StatsSectionModel: Identifiable {
    var id: StatsMetricKind { metric }
    let metric: StatsMetricKind
    let title: String
    let description: String?
    let series: [WeeklyMetricValue]
    let baseline: BaselineResult?
    let breakdown: [BreakdownItem]
}

struct AlertModel: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let metric: StatsMetricKind?
}

struct MetricDetailModel: Identifiable {
    let id = UUID()
    let metric: StatsMetricKind
    let title: String
    let series: [WeeklyMetricValue]
    let baseline: BaselineResult?
    let contextLines: [String]
    let breakdown: [BreakdownItem]
    let learnMore: [String]
}

struct StatsDashboardResult {
    let mode: StatsMode
    let range: StatsRange
    let filter: StatsExerciseFilter
    let cards: [TrendCardModel]
    let minimumStrip: [MinimumStripMetric]
    let sections: [StatsSectionModel]
    let alerts: [AlertModel]
    let muscles: [MuscleOverviewModel]
    let detail: [StatsMetricKind: MetricDetailModel]

    static func empty(mode: StatsMode, range: StatsRange, filter: StatsExerciseFilter) -> StatsDashboardResult {
        StatsDashboardResult(
            mode: mode,
            range: range,
            filter: filter,
            cards: [],
            minimumStrip: [],
            sections: [],
            alerts: [],
            muscles: [],
            detail: [:]
        )
    }
}

struct MuscleOverviewModel: Identifiable {
    var id: MuscleGroup { muscle }
    let muscle: MuscleGroup
    let weekly: [WeeklyMetricValue]
    let floor: Double
    let band: ClosedRange<Double>
    let topExercises: [BreakdownItem]

    var latestSets: Int {
        Int(weekly.last?.value ?? 0)
    }
}

// MARK: - Legacy stats models (used by Friend detail + coach)

enum StatsLens: String, CaseIterable, Identifiable, Codable, Hashable {
    case week = "Week"
    case month = "Month"
    case all = "All-time"

    var id: String { rawValue }
}

enum MuscleGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case legs = "Legs"
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
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .legs: return "Legs"
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
