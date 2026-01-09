import Foundation

struct CloudSyncState: Codable {
    var lastSyncedEndedAt: Date?
    var syncedSessionIds: [String] = [] // simple FIFO to avoid duplicate syncs

    private static let storageKey = "cloudSyncState"
    private static let maxSyncedIds = 50

    static func load() -> CloudSyncState {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(CloudSyncState.self, from: data) else {
            return CloudSyncState()
        }
        return state
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    mutating func markSynced(sessionId: UUID, endedAt: Date) {
        lastSyncedEndedAt = maxDate(lastSyncedEndedAt, endedAt)
        syncedSessionIds.append(sessionId.uuidString)
        if syncedSessionIds.count > Self.maxSyncedIds {
            syncedSessionIds.removeFirst(syncedSessionIds.count - Self.maxSyncedIds)
        }
        save()
    }

    private func maxDate(_ a: Date?, _ b: Date) -> Date {
        guard let a else { return b }
        return a > b ? a : b
    }
}
