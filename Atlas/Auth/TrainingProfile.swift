import Foundation

struct TrainingProfile: Codable, Equatable, Sendable {
    var heightCm: Double?
    var weightKg: Double?
    var workoutsPerWeek: Int?
    var goal: String?
    var experienceLevel: String?
    var limitations: String?
    var onboardingCompleted: Bool

    static let empty = TrainingProfile(heightCm: nil, weightKg: nil, workoutsPerWeek: nil, goal: nil, experienceLevel: nil, limitations: nil, onboardingCompleted: false)

    var isComplete: Bool {
        heightCm != nil && weightKg != nil && workoutsPerWeek != nil && goal?.isEmpty == false && experienceLevel?.isEmpty == false
    }
}
