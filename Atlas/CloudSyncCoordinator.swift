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
    private var state: CloudSyncStateStore
    private var didStart = false
    private var inflight: Set<UUID> = []
    private var lastAttempt: [UUID: Date] = [:]
    private var lastFailureAt: Date?
    private var cooldownSeconds: TimeInterval = 0

    init(historyStore: HistoryStore, authStore: AuthStore) {
        self.historyStore = historyStore
        self.authStore = authStore
        self.state = CloudSyncStateStore()
        if let client = authStore.supabaseClient {
            self.service = CloudSyncService(client: client)
        }
    }

    func startIfNeeded() async {
        guard didStart == false else { return }
        didStart = true
        configureService()
        await syncIfNeeded(reason: "startup")
    }

    func syncEndedSessionsIfNeeded() async {
        await syncIfNeeded(reason: "endSession")
    }

    func sync(summary: WorkoutSessionCloudSummary) async {
        guard let service else { return }
        guard authStore.isAuthenticated else { return }
        do {
            try await service.upsertWorkoutSessionSummary(summary)
            #if DEBUG
            print("[CLOUDSYNC] upsert ok session=\(summary.sessionId)")
            #endif
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            print("[CLOUDSYNC][ERROR] session=\(summary.sessionId) error=\(error)")
            #endif
        }
    }

    private func configureService() {
        guard let client = authStore.supabaseClient, authStore.isAuthenticated else {
            service = nil
            return
        }
        service = CloudSyncService(client: client)
    }

    func syncIfNeeded(reason: String) async {
        guard isSyncing == false else { return }
        guard let service else { return }
        guard authStore.isAuthenticated else { return }
        if let failureAt = lastFailureAt, cooldownSeconds > 0 {
            let elapsed = Date().timeIntervalSince(failureAt)
            if elapsed < cooldownSeconds {
                #if DEBUG
                let remaining = Int(cooldownSeconds - elapsed)
                print("[CLOUDSYNC] skipped push (cooldown) remaining=\(remaining)s")
                #endif
                return
            }
        }
        isSyncing = true
        lastError = nil
        #if DEBUG
        print("[CLOUDSYNC] start reason=\(reason)")
        #endif
        defer { isSyncing = false }
        let sessions = historyStore.endedSessions(after: nil, limit: 500)
        let ordered = sessions
            .filter { $0.endedAt != nil && $0.totalSets > 0 }
            .sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }

        let filtered = ordered.filter { session in
            guard let ended = session.endedAt else { return false }
            if state.isSynced(sessionId: session.id, endedAt: ended) { return false }
            return true
        }

        #if DEBUG
        let lastSyncedDesc = state.lastSyncedEndedAt?.description ?? "nil"
        print("[CLOUDSYNC] candidates=\(ordered.count) uploading=\(filtered.count) lastSyncedEndedAt=\(lastSyncedDesc)")
        #endif

        for session in filtered {
            guard let ended = session.endedAt else { continue }
            if inflight.contains(session.id) {
                #if DEBUG
                print("[CLOUDSYNC] skip duplicate inflight session=\(session.id)")
                #endif
                continue
            }
            if let last = lastAttempt[session.id], Date().timeIntervalSince(last) < 2 {
                #if DEBUG
                print("[CLOUDSYNC] skip recent duplicate session=\(session.id)")
                #endif
                continue
            }
            inflight.insert(session.id)
            lastAttempt[session.id] = Date()
            defer { inflight.remove(session.id) }
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
                lastFailureAt = nil
                cooldownSeconds = 0
                #if DEBUG
                print("[CLOUDSYNC] upsert ok session=\(session.id)")
                #endif
            } catch {
                lastError = error.localizedDescription
                lastFailureAt = Date()
                if cooldownSeconds == 0 {
                    cooldownSeconds = 30
                } else {
                    cooldownSeconds = min(cooldownSeconds * 2, 300)
                }
                #if DEBUG
                print("[CLOUDSYNC][ERROR] session=\(session.id) error=\(error)")
                #endif
            }
        }
        lastSyncAt = Date()
        #if DEBUG
        print("[CLOUDSYNC] done")
        #endif
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
