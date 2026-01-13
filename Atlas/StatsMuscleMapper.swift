import Foundation

enum BalanceTag {
    case push
    case pull
    case quad
    case hinge
    case carry
}

struct MuscleInfo {
    let primary: MuscleGroup
    let secondary: [MuscleGroup]
    let balance: Set<BalanceTag>
}

enum StatsMuscleMapper {
    private static let keywordMap: [(keywords: [String], primary: MuscleGroup, secondary: [MuscleGroup], balance: Set<BalanceTag>)] = [
        (["bench", "press", "chest press"], .chest, [.shoulders, .arms], [.push]),
        (["incline"], .chest, [.shoulders, .arms], [.push]),
        (["ohp", "overhead press", "shoulder press"], .shoulders, [.arms], [.push]),
        (["row", "pull"], .back, [.arms], [.pull]),
        (["pulldown", "pull-down", "lat"], .back, [.arms], [.pull]),
        (["squat", "leg press"], .legs, [.core], [.quad]),
        (["lunge", "split squat"], .legs, [.core], [.quad]),
        (["deadlift", "rdl", "hinge"], .legs, [.back, .core], [.hinge]),
        (["hip thrust", "glute"], .legs, [.core], [.hinge]),
        (["curl"], .arms, [.back], [.pull]),
        (["extension", "pushdown", "pressdown", "tricep"], .arms, [.chest, .shoulders], [.push]),
        (["calf"], .legs, [], [.quad]),
        (["lateral raise"], .shoulders, [], [.push]),
        (["carry", "farmer"], .core, [.arms], [.carry]),
        (["plank", "ab", "core", "hollow", "pallof"], .core, [], [])
    ]

    static func info(for exerciseName: String) -> MuscleInfo {
        let lower = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for entry in keywordMap {
            if entry.keywords.contains(where: { lower.contains($0) }) {
                return MuscleInfo(primary: entry.primary, secondary: entry.secondary, balance: entry.balance)
            }
        }

        // Fallback heuristics
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull") {
            return MuscleInfo(primary: .back, secondary: [.arms], balance: [.pull])
        }
        if lower.contains("press") || lower.contains("push") {
            return MuscleInfo(primary: .chest, secondary: [.shoulders, .arms], balance: [.push])
        }
        if lower.contains("squat") || lower.contains("quad") || lower.contains("leg") {
            return MuscleInfo(primary: .legs, secondary: [.core], balance: [.quad])
        }
        if lower.contains("hinge") || lower.contains("deadlift") || lower.contains("rdl") {
            return MuscleInfo(primary: .legs, secondary: [.back, .core], balance: [.hinge])
        }
        if lower.contains("shoulder") || lower.contains("delt") {
            return MuscleInfo(primary: .shoulders, secondary: [.arms], balance: [.push])
        }
        return MuscleInfo(primary: .core, secondary: [], balance: [])
    }
}
