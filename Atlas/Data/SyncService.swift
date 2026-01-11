import Foundation
import SwiftData
import Supabase

struct RemoteRoutinePayload: Codable {
    let id: UUID
    let owner_user_id: UUID
    let user_id: UUID
    let local_id: String
    let title: String
    let tags: [String]
    let is_coach_suggested: Bool
    let coach_name: String?
    let payload: String
    let is_deleted: Bool
    let updated_at: Date
    let created_at: Date
}

struct RemoteSessionRow: Codable {
    let id: UUID
    let user_id: UUID
    let local_id: String
    let routine_id: UUID?
    let routine_title: String
    let started_at: Date
    let ended_at: Date
    let total_sets: Int
    let total_reps: Int
    let total_volume_kg: Double
    let created_at: Date
}

struct RemoteExerciseRow: Codable {
    let id: UUID
    let session_id: UUID
    let user_id: UUID
    let local_id: String
    let name: String
    let sort_index: Int
    let created_at: Date
}

struct RemoteSetRow: Codable {
    let id: UUID
    let exercise_id: UUID
    let session_id: UUID
    let user_id: UUID
    let local_id: String
    let weight_kg: Double
    let reps: Int
    let is_bodyweight: Bool
    let is_warmup: Bool
    let created_at: Date
}

struct RemoteTagRow: Codable {
    let id: UUID
    let set_id: UUID
    let user_id: UUID
    let tag: String
    let created_at: Date
}

@MainActor
final class SyncService {
    private let modelContext: ModelContext
    private weak var routineStore: RoutineStore?
    private weak var historyStore: HistoryStore?
    private weak var authStore: AuthStore?
    private var isProcessing = false

    private let sessionWatermarkKey = "SyncState.sessionsUpdatedAt"
    private let routinesWatermarkKey = "SyncState.routinesUpdatedAt"
    private var lastSessionFailure: [UUID: Date] = [:]
    private var lastRoutineFailure: Date?

    init(modelContext: ModelContext, authStore: AuthStore, routineStore: RoutineStore, historyStore: HistoryStore) {
        self.modelContext = modelContext
        self.authStore = authStore
        self.routineStore = routineStore
        self.historyStore = historyStore
    }

    // MARK: - v1 push helpers

    func pushCompletedSessions(limit: Int = 10) async {
        guard let client = authStore?.supabaseClient, let userId = authStore?.currentUserId else { return }
        let sessions = historyStore?.recentSessions(limit: limit).filter { $0.endedAt != nil && $0.totalSets > 0 } ?? []
        for session in sessions {
            if let lastFail = lastSessionFailure[session.id], Date().timeIntervalSince(lastFail) < 60 {
                #if DEBUG
                print("[SYNC][PUSH] skip cooldown session=\(session.id)")
                #endif
                continue
            }
            guard let graph = buildSessionGraph(session: session, userId: userId) else { continue }
            do {
                try await client.database.from("workout_sessions")
                    .upsert(graph.session, onConflict: "id", returning: .minimal)
                    .execute()
                if !graph.exercises.isEmpty {
                    try await client.database.from("session_exercises")
                        .upsert(graph.exercises, onConflict: "id", returning: .minimal)
                        .execute()
                }
                if !graph.sets.isEmpty {
                    try await client.database.from("session_sets")
                        .upsert(graph.sets, onConflict: "id", returning: .minimal)
                        .execute()
                }
                if !graph.tags.isEmpty {
                    try await client.database.from("session_set_tags")
                        .upsert(graph.tags, onConflict: "set_id,tag", returning: .minimal)
                        .execute()
                }
                lastSessionFailure[session.id] = nil
            } catch {
                lastSessionFailure[session.id] = Date()
                #if DEBUG
                let uidShort = userId.uuidString.prefix(6)
                print("[SYNC][PUSH][ERROR] session=\(session.id) user=\(uidShort) table=history error=\(error)")
                #endif
            }
        }
    }

    func upsertAllRoutines() async {
        guard let client = authStore?.supabaseClient, let userId = authStore?.currentUserId, let store = routineStore else { return }
        let payloads = store.routines.map { routinePayload(for: $0, userId: userId) }
        guard !payloads.isEmpty else { return }
        if let lastFail = lastRoutineFailure, Date().timeIntervalSince(lastFail) < 60 {
            #if DEBUG
            print("[SYNC][ROUTINES] skip cooldown \(payloads.count) items")
            #endif
            return
        }
        do {
            try await client.database.from("routines")
                .upsert(payloads, onConflict: "id", returning: .minimal)
                .execute()
            #if DEBUG
            print("[SYNC][ROUTINES] upsert ok count=\(payloads.count)")
            #endif
            lastRoutineFailure = nil
        } catch {
            lastRoutineFailure = Date()
            #if DEBUG
            let uidShort = userId.uuidString.prefix(6)
            print("[SYNC][ROUTINES][ERROR] user=\(uidShort) error=\(error)")
            #endif
        }
    }

    func deleteRoutineRemote(routine: Routine) async {
        guard let client = authStore?.supabaseClient, let userId = authStore?.currentUserId else { return }
        do {
            let payload = RemoteRoutinePayload(
                id: routine.id,
                owner_user_id: userId,
                user_id: userId,
                local_id: routine.id.uuidString,
                title: routine.name,
                tags: muscleTags(for: routine).map { $0.rawValue },
                is_coach_suggested: routine.isCoachSuggested,
                coach_name: routine.coachDisplayName,
                payload: "{}",
                is_deleted: true,
                updated_at: Date(),
                created_at: Date()
            )
            try await client.database.from("routines")
                .upsert(payload, onConflict: "id", returning: .minimal)
                .execute()
        } catch {
            #if DEBUG
            print("[SYNC][ROUTINES] delete failed: \(error)")
            #endif
        }
    }

    /// Convenience for existing call sites: push recent completed sessions and upsert all routines.
    func processOutboxAndPull() async {
        await pushCompletedSessions(limit: 10)
        await upsertAllRoutines()
    }

    /// Back-compat wrapper for older call sites that expected a routine upsert enqueue.
    func enqueueRoutineUpsert(_ routine: Routine) async {
        await upsertAllRoutines()
    }

    /// Back-compat wrapper for older call sites that expected a "sync now" entry point.
    func syncNow() async {
        await processOutboxAndPull()
    }

    private func saveContext() {
        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

}

private extension SyncService {
    func buildSessionGraph(session: WorkoutSession, userId: UUID) -> (session: RemoteSessionRow, exercises: [RemoteExerciseRow], sets: [RemoteSetRow], tags: [RemoteTagRow])? {
        guard let ended = session.endedAt else { return nil }
        let sessionRow = RemoteSessionRow(
            id: session.id,
            user_id: userId,
            local_id: session.id.uuidString,
            routine_id: session.routineTemplateId,
            routine_title: session.routineTitle,
            started_at: session.startedAt,
            ended_at: ended,
            total_sets: session.totalSets,
            total_reps: session.totalReps,
            total_volume_kg: session.volumeKg,
            created_at: Date()
        )
        var exercises: [RemoteExerciseRow] = []
        var sets: [RemoteSetRow] = []
        var tags: [RemoteTagRow] = []
        for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let exerciseRow = RemoteExerciseRow(
                id: exercise.id,
                session_id: sessionRow.id,
                user_id: userId,
                local_id: exercise.id.uuidString,
                name: exercise.name,
                sort_index: exercise.orderIndex,
                created_at: Date()
            )
            exercises.append(exerciseRow)
            for set in exercise.sets.sorted(by: { $0.createdAt < $1.createdAt }) {
                let isBodyweight = set.weightKg == nil
                let setRow = RemoteSetRow(
                    id: set.id,
                    exercise_id: exerciseRow.id,
                    session_id: sessionRow.id,
                    user_id: userId,
                    local_id: set.id.uuidString,
                    weight_kg: set.weightKg ?? 0,
                    reps: set.reps,
                    is_bodyweight: isBodyweight,
                    is_warmup: set.tagRaw == "W",
                    created_at: set.createdAt
                )
                sets.append(setRow)
                let tagValue = set.tagRaw
                let tagRow = RemoteTagRow(
                    id: UUID(),
                    set_id: setRow.id,
                    user_id: userId,
                    tag: tagValue,
                    created_at: Date()
                )
                tags.append(tagRow)
            }
        }
        return (sessionRow, exercises, sets, tags)
    }

    func routinePayload(for routine: Routine, userId: UUID) -> RemoteRoutinePayload {
        let encoded = (try? JSONEncoder().encode(routine)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let tags = muscleTags(for: routine).map { $0.rawValue }
        return RemoteRoutinePayload(
            id: routine.id,
            owner_user_id: userId,
            user_id: userId,
            local_id: routine.id.uuidString,
            title: routine.name,
            tags: tags,
            is_coach_suggested: routine.isCoachSuggested,
            coach_name: routine.coachDisplayName,
            payload: encoded,
            is_deleted: false,
            updated_at: Date(),
            created_at: Date()
        )
    }

    func muscleTags(for routine: Routine) -> [MuscleGroup] {
        var counts: [MuscleGroup: Int] = [:]
        for workout in routine.workouts {
            let lower = workout.name.lowercased()
            func contains(_ keywords: [String]) -> Bool {
                keywords.contains { lower.contains($0) }
            }
            if contains(["squat", "lunge", "leg press", "rdl", "deadlift", "calf"]) {
                counts[.legs, default: 0] += 1
            }
            if contains(["row", "pulldown", "pull-up", "pullup", "lat", "rear delt"]) {
                counts[.back, default: 0] += 1
            }
            if contains(["bench", "press", "fly"]) {
                counts[.chest, default: 0] += 1
            }
            if contains(["ohp", "shoulder", "overhead", "lateral raise", "face pull"]) {
                counts[.shoulders, default: 0] += 1
            }
            if contains(["curl", "bicep", "tricep", "extension", "pushdown", "dip"]) {
                counts[.arms, default: 0] += 1
            }
            if contains(["plank", "crunch", "ab", "core", "carry"]) {
                counts[.core, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }
}

private extension RoutineStore {
    func upsertRoutine(_ routine: Routine) {
        if routines.contains(where: { $0.id == routine.id }) {
            if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
                routines[idx] = routine
            }
        } else {
            routines.insert(routine, at: 0)
        }
        save()
    }

    func removeRoutineLocally(id: UUID) {
        routines.removeAll { $0.id == id }
        save()
    }
}
