import Foundation

enum StatsMode: String, CaseIterable, Identifiable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case athletic = "Athletic"

    var id: String { rawValue }

    var title: String { rawValue }
}
