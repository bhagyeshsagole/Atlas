import Foundation
import SwiftData
import Supabase

struct RemoteRoutinePayload: Codable {
    let id: UUID
    let user_id: UUID
    let local_id: String
    let group_id: String
    let title: String
    let is_coach_suggested: Bool
    let deleted_at: Date?
    let created_at: Date
    let updated_at: Date
}

struct RemoteRoutineExerciseRow: Codable {
    let id: UUID
    let user_id: UUID
    let routine_id: UUID
    let local_id: String
    let exercise_name: String
    let sort_order: Int
    let created_at: Date
    let updated_at: Date
}

struct RemoteSessionRow: Codable {
    let id: UUID
    let user_id: UUID
    let local_id: String
    let routine_local_id: String?
    let routine_title: String
    let started_at: Date
    let ended_at: Date
    let total_sets: Int
    let total_reps: Int
    let total_volume_kg: Double
    let created_at: Date
    let updated_at: Date
}

struct RemoteExerciseRow: Codable {
    let id: UUID
    let session_id: UUID
    let user_id: UUID
    let local_id: String
    let exercise_name: String
    let sort_order: Int
    let created_at: Date
    let updated_at: Date
}

struct RemoteSetRow: Codable {
    let id: UUID
    let session_exercise_id: UUID
    let user_id: UUID
    let local_id: String
    let performed_at: Date
    let weight_kg: Double
    let reps: Int
    let entered_unit: String?
    let tag: String?
    let created_at: Date
    let updated_at: Date
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
                    .upsert(graph.session, onConflict: "local_id", returning: .minimal)
                    .execute()
                if !graph.exercises.isEmpty {
                    try await client.database.from("session_exercises")
                        .upsert(graph.exercises, onConflict: "local_id", returning: .minimal)
                        .execute()
                }
                if !graph.sets.isEmpty {
                    try await client.database.from("set_logs")
                        .upsert(graph.sets, onConflict: "local_id", returning: .minimal)
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
        let exerciseRows = store.routines.flatMap { routineExerciseRows(for: $0, userId: userId) }
        guard !payloads.isEmpty else { return }
        if let lastFail = lastRoutineFailure, Date().timeIntervalSince(lastFail) < 60 {
            #if DEBUG
            print("[SYNC][ROUTINES] skip cooldown \(payloads.count) items")
            #endif
            return
        }
        do {
            try await client.database.from("routines")
                .upsert(payloads, onConflict: "local_id", returning: .minimal)
                .execute()
            if !exerciseRows.isEmpty {
                try await client.database.from("routine_exercises")
                    .upsert(exerciseRows, onConflict: "local_id", returning: .minimal)
                    .execute()
            }
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
                user_id: userId,
                local_id: routine.id.uuidString,
                group_id: routine.groupId,
                title: routine.name,
                is_coach_suggested: routine.isCoachSuggested,
                deleted_at: Date(),
                created_at: routine.createdAt,
                updated_at: Date()
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
    func buildSessionGraph(session: WorkoutSession, userId: UUID) -> (session: RemoteSessionRow, exercises: [RemoteExerciseRow], sets: [RemoteSetRow])? {
        guard let ended = session.endedAt else { return nil }
        let sessionRow = RemoteSessionRow(
            id: session.id,
            user_id: userId,
            local_id: session.id.uuidString,
            routine_local_id: session.routineTemplateId?.uuidString,
            routine_title: session.routineTitle,
            started_at: session.startedAt,
            ended_at: ended,
            total_sets: session.totalSets,
            total_reps: session.totalReps,
            total_volume_kg: session.volumeKg,
            created_at: Date(),
            updated_at: Date()
        )
        var exercises: [RemoteExerciseRow] = []
        var sets: [RemoteSetRow] = []
        for exercise in session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            let exerciseRow = RemoteExerciseRow(
                id: exercise.id,
                session_id: sessionRow.id,
                user_id: userId,
                local_id: exercise.id.uuidString,
                exercise_name: exercise.name,
                sort_order: exercise.orderIndex,
                created_at: Date(),
                updated_at: Date()
            )
            exercises.append(exerciseRow)
            for set in exercise.sets.sorted(by: { $0.createdAt < $1.createdAt }) {
                let setRow = RemoteSetRow(
                    id: set.id,
                    session_exercise_id: exerciseRow.id,
                    user_id: userId,
                    local_id: set.id.uuidString,
                    performed_at: set.createdAt,
                    weight_kg: set.weightKg ?? 0,
                    reps: set.reps,
                    entered_unit: set.enteredUnitRaw,
                    tag: set.tagRaw,
                    created_at: set.createdAt,
                    updated_at: Date()
                )
                sets.append(setRow)
            }
        }
        return (sessionRow, exercises, sets)
    }

    func routinePayload(for routine: Routine, userId: UUID) -> RemoteRoutinePayload {
        RemoteRoutinePayload(
            id: routine.id,
            user_id: userId,
            local_id: routine.id.uuidString,
            group_id: routine.groupId,
            title: routine.name,
            is_coach_suggested: routine.isCoachSuggested,
            deleted_at: nil,
            created_at: routine.createdAt,
            updated_at: Date()
        )
    }

    func routineExerciseRows(for routine: Routine, userId: UUID) -> [RemoteRoutineExerciseRow] {
        routine.workouts.enumerated().map { index, workout in
            RemoteRoutineExerciseRow(
                id: workout.id,
                user_id: userId,
                routine_id: routine.id,
                local_id: workout.id.uuidString,
                exercise_name: workout.name,
                sort_order: index,
                created_at: routine.createdAt,
                updated_at: Date()
            )
        }
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
            if contains(["curl", "bicep"]) {
                counts[.biceps, default: 0] += 1
            }
            if contains(["tricep", "extension", "pushdown", "dip"]) {
                counts[.triceps, default: 0] += 1
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
