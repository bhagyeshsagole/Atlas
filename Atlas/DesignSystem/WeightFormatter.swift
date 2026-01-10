import Foundation

enum WeightFormatter {
    static func format(_ weightKg: Double?, unit: WorkoutUnits, includeUnit: Bool = true) -> String {
        guard let weightKg else { return "Bodyweight" }
        let value: Double
        let unitLabel: String
        switch unit {
        case .kg:
            value = weightKg
            unitLabel = "kg"
        case .lb:
            value = weightKg * WorkoutSessionFormatter.kgToLb
            unitLabel = "lb"
        }

        let formatted = String(format: "%.1f", value)
        return includeUnit ? "\(formatted) \(unitLabel)" : formatted
    }
}
