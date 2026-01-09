import Foundation

struct CloudSyncSyncedSession: Codable {
    let endedAtISO: String
    let syncedAtISO: String
}

struct CloudSyncPersistedState: Codable {
    var bySessionId: [String: CloudSyncSyncedSession] = [:]
}

final class CloudSyncStateStore: @unchecked Sendable {
    private let storageKey = "cloudsync.state.sessions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private var state: CloudSyncPersistedState

    init() {
        state = CloudSyncPersistedState()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode(CloudSyncPersistedState.self, from: data) {
            state = decoded
        }
    }

    func isSynced(sessionId: UUID, endedAt: Date) -> Bool {
        let key = sessionId.uuidString
        guard let entry = state.bySessionId[key] else { return false }
        return entry.endedAtISO == isoFormatter.string(from: endedAt)
    }

    func markSynced(sessionId: UUID, endedAt: Date) {
        let key = sessionId.uuidString
        let entry = CloudSyncSyncedSession(
            endedAtISO: isoFormatter.string(from: endedAt),
            syncedAtISO: isoFormatter.string(from: Date())
        )
        state.bySessionId[key] = entry
        persist()
    }

    var lastSyncedEndedAt: Date? {
        let dates = state.bySessionId.values.compactMap { isoFormatter.date(from: $0.endedAtISO) }
        return dates.max()
    }

    private func persist() {
        if let data = try? encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
