import Foundation

final class TrainingProfileStore {
    private let defaults: UserDefaults
    private let keyPrefix = "atlas.trainingProfile"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for userId: UUID) -> TrainingProfile? {
        let key = storageKey(userId: userId)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TrainingProfile.self, from: data)
    }

    func save(_ profile: TrainingProfile, for userId: UUID) {
        let key = storageKey(userId: userId)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: key)
        }
    }

    private func storageKey(userId: UUID) -> String {
        "\(keyPrefix).\(userId.uuidString)"
    }
}
