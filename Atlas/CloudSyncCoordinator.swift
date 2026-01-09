import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
final class CloudSyncCoordinator: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var lastError: String?
    @Published var lastSyncAt: Date?

    private let historyStore: HistoryStore
    private let authStore: AuthStore
    private var service: CloudSyncService?
    private var state: CloudSyncState
    private var didStart = false

    init(historyStore: HistoryStore, authStore: AuthStore) {
        self.historyStore = historyStore
        self.authStore = authStore
        self.state = CloudSyncState.load()
        if let client = authStore.supabaseClient {
            self.service = CloudSyncService(client: client)
        }
    }

    func startIfNeeded() async {
        guard didStart == false else { return }
        didStart = true
        configureService()
        await syncNow(reason: "startup")
    }

    func syncEndedSessionsIfNeeded() async {
        await syncNow(reason: "manual")
    }

    private func configureService() {
        guard let client = authStore.supabaseClient, authStore.isAuthenticated else {
            service = nil
            return
        }
        service = CloudSyncService(client: client)
    }

    func syncNow(reason: String) async {
        guard isSyncing == false else { return }
        guard let service else { return }
        guard authStore.isAuthenticated else { return }
        isSyncing = true
        lastError = nil
        #if DEBUG
        print("[CLOUDSYNC] syncing reason=\(reason)")
        #endif
        defer { isSyncing = false }
        let sessions = historyStore.endedSessions(after: state.lastSyncedEndedAt, limit: 200)
        let ordered = sessions.sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        for session in ordered {
            guard let ended = session.endedAt, session.totalSets > 0 else { continue }
            let summary = WorkoutSessionCloudSummary(
                sessionId: session.id,
                routineTitle: session.routineTitle.isEmpty ? "Untitled" : session.routineTitle,
                startedAt: session.startedAt,
                endedAt: ended,
                totalSets: session.totalSets,
                totalReps: session.totalReps,
                volumeKg: session.volumeKg
            )
            do {
                try await service.upsertWorkoutSessionSummary(summary)
                state.markSynced(sessionId: session.id, endedAt: ended)
                #if DEBUG
                print("[CLOUDSYNC] upsert ok session=\(session.id)")
                #endif
            } catch {
                lastError = error.localizedDescription
                #if DEBUG
                print("[CLOUDSYNC][ERROR] session=\(session.id) error=\(error)")
                #endif
                return
            }
        }
        lastSyncAt = Date()
    }

    #if DEBUG
    func debugPrintStatus(historyStore: HistoryStore) {
        let sessions = historyStore.endedSessions(after: nil, limit: 1000)
        let lastSynced = state.lastSyncedEndedAt?.description ?? "nil"
        let newestLocal = sessions.compactMap(\.endedAt).max()?.description ?? "nil"
        print("[CLOUDSYNC][DEBUG] localEndedCount=\(sessions.count) lastSyncedEndedAt=\(lastSynced) newestLocalEndedAt=\(newestLocal) lastError=\(lastError ?? "nil")")
    }
    #endif
}
