//
//  HistoryStore.swift
//  Atlas
//
//  What this file is:
//  - Central SwiftData writer/reader for workout sessions, exercises, sets, and calendar data.
//
//  Where it’s used:
//  - Injected from `AtlasApp` and called by logging screens (WorkoutSessionView), home calendar, and history lists.
//
//  Called from:
//  - `ContentView` runs repair on appear; `WorkoutSessionView` uses it to start/end sessions and add sets; `DevHistorySeeder` seeds via this store.
//
//  Key concepts:
//  - `ModelContext` is the SwiftData connection for reading/writing persisted models.
//  - Methods here mutate data and then save; SwiftUI views observing the data update automatically.
//
//  Safe to change:
//  - Add new helper queries, adjust debug logs, or expand calculations if you also handle migrations.
//
//  NOT safe to change:
//  - Delete or skip `saveContext()` calls; writes would be lost.
//  - Remove the discard rule for zero-set sessions without checking UI expectations.
//
//  Common bugs / gotchas:
//  - Forgetting to fetch via `FetchDescriptor` can lead to stale data; always operate on the live context.
//  - Editing totals without recalculating volume can desync stats.
//
//  DEV MAP:
//  - See: DEV_MAP.md → C) Workout Sessions / History (real performance logs)
//
// FLOW SUMMARY:
// WorkoutSessionView starts/ends sessions → HistoryStore saves sets and totals → SwiftData persists → HomeView/History views query HistoryStore/SwiftData for calendar + cards.
//

import Foundation
import Combine
import SwiftData
import Supabase

/// Minimal remote history graph used when importing sessions pulled from Supabase.
/// Kept local to avoid target-membership issues; mirror fields the sync layer returns.
struct RemoteSessionGraph {
    struct Session: Codable {
        let id: UUID
        let routine_id: UUID?
        let routine_title: String
        let started_at: Date
        let ended_at: Date?
        let total_sets: Int
        let total_reps: Int
        let total_volume_kg: Double
    }

    struct Exercise: Codable {
        let id: UUID
        let session_id: UUID?
        let exercise_name: String
        let sort_index: Int
    }

    struct Set: Codable {
        let id: UUID
        let exercise_log_id: UUID
        let reps: Int
        let weight_kg: Double
        let tag: String?
        let created_at: Date?
    }
}

/// DEV MAP: History writes/reads live here (queries, discard rules, calendar data).
/// DEV NOTE: ALL history writes go through HistoryStore so UI + AI always agree.
/// DEV NOTE: Queries avoid #Predicate macros to prevent SwiftData macro compiler issues.
@MainActor
final class HistoryStore: ObservableObject {
    private let modelContext: ModelContext // Shared SwiftData context injected at app boot.
    private let calendar = Calendar.current
    private var cloudSyncService: CloudSyncService?
    weak var cloudSyncCoordinator: CloudSyncCoordinator?
    weak var syncService: SyncService?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func configureCloudSync(client: SupabaseClient?) {
        guard let client else {
            cloudSyncService = nil
            return
        }
        cloudSyncService = CloudSyncService(client: client)
    }

    func configureCloudSyncCoordinator(_ coordinator: CloudSyncCoordinator?) {
        cloudSyncCoordinator = coordinator
    }

    func configureSyncService(_ service: SyncService?) {
        syncService = service
    }

    func startSession(routineId: UUID?, routineTitle: String, exercises: [String], routineTemplateId: UUID? = nil) -> WorkoutSession {
        // Re-entrancy guard: reuse any active draft for the same routine to avoid duplicate starts.
        if let active = existingActiveSession(routineId: routineId, routineTitle: routineTitle) {
            return active
        }

        let session = WorkoutSession(
            routineId: routineId,
            routineTemplateId: routineTemplateId ?? routineId,
            routineTitle: routineTitle,
            startedAt: Date(),
            endedAt: nil,
            totalSets: 0,
            totalReps: 0,
            volumeKg: 0,
            aiPostSummaryText: "",
            aiPostSummaryJSON: "",
            rating: nil,
            isCompleted: false,
            exercises: []
        )

        for (index, name) in exercises.enumerated() {
            let exercise = ExerciseLog(name: name, orderIndex: index, session: session)
            session.exercises.append(exercise)
        }

        modelContext.insert(session)
        saveContext(reason: "startSession")

        #if DEBUG
        let exerciseList = exercises.joined(separator: ", ")
        print("[HISTORY] start session id=\(session.id) routine=\(routineTitle) exercises=\(exerciseList)")
        #endif

        return session
    }

    func addSet(
        session: WorkoutSession,
        exerciseName: String,
        orderIndex: Int,
        tag: SetTag,
        weightKg: Double?,
        reps: Int,
        enteredUnit: WorkoutUnits = .kg
    ) {
        // Try to reuse an exercise by order, then by name, else make a new exercise row.
        let exerciseLog = session.exercises.first(where: { $0.orderIndex == orderIndex })
            ?? session.exercises.first(where: { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame })
            ?? {
                let newExercise = ExerciseLog(name: exerciseName, orderIndex: orderIndex, session: session)
                session.exercises.append(newExercise)
                return newExercise
            }()

        let set = SetLog(tag: tag.rawValue, weightKg: weightKg, reps: reps, enteredUnit: enteredUnit, createdAt: Date(), exercise: exerciseLog)
        exerciseLog.sets.append(set)

        saveContext(reason: "addSet")

        #if DEBUG
        let weightDisplay = weightKg.map { String(format: "%.2f", $0) } ?? "nil"
        let totalSetCount = session.exercises.reduce(0) { $0 + $1.sets.count }
        print("[HISTORY] addSet session=\(session.id) ex=\(exerciseName) tag=\(tag.rawValue) kg=\(weightDisplay) reps=\(reps)")
        print("[HISTORY] session now has sets=\(totalSetCount)")
        #endif
    }

    func deleteSet(_ set: SetLog, from session: WorkoutSession) {
        guard let exercise = set.exercise else { return }
        exercise.sets.removeAll { $0.id == set.id }
        modelContext.delete(set)
        saveContext(reason: "deleteSet")
        #if DEBUG
        let totalSetCount = session.exercises.reduce(0) { $0 + $1.sets.count }
        print("[HISTORY] deleteSet session=\(session.id) ex=\(exercise.name) remainingSets=\(exercise.sets.count) totalSessionSets=\(totalSetCount)")
        #endif
    }

    /// Returns true if the session was stored, false if discarded for zero sets.
    func endSession(session: WorkoutSession) -> Bool {
        let registeredSession: WorkoutSession? = modelContext.registeredModel(for: session.id)
        guard let liveSession = resolvedSession(for: session.id) ?? registeredSession ?? (session.modelContext != nil ? session : nil) else {
            #if DEBUG
            print("[HISTORY][ERROR] end session failed: session not found id=\(session.id)")
            #endif
            return false
        }

        if liveSession.isCompleted || liveSession.endedAt != nil {
            #if DEBUG
            print("[HISTORY] end session already completed id=\(liveSession.id)")
            #endif
            return true
        }

        let totals = computeTotals(for: liveSession)

        liveSession.totalSets = totals.sets
        liveSession.totalReps = totals.reps
        liveSession.volumeKg = totals.volumeKg

        liveSession.endedAt = Date()
        liveSession.isCompleted = true
        if let end = liveSession.endedAt {
            liveSession.durationSeconds = max(0, Int(end.timeIntervalSince(liveSession.startedAt)))
        }

        let saved = saveContext(reason: "endSession")

        #if DEBUG
        logPersistenceCheck(for: liveSession.id)
        if saved {
            print("[HISTORY] end session id=\(liveSession.id) stored=true sets=\(totals.sets) reps=\(totals.reps) volumeKg=\(String(format: "%.2f", totals.volumeKg))")
        }
        #endif

        if saved, totals.sets > 0, let coordinator = cloudSyncCoordinator {
            if let summary = liveSession.cloudSummary {
                Task.detached {
                    await coordinator.sync(summary: summary)
                }
            }
        }

        if saved, totals.sets > 0 {
            Task.detached { [weak syncService] in
                await syncService?.pushCompletedSessions(limit: 10)
            }
        }

        return saved
    }

    func endedSessions(after date: Date?, limit: Int = 50) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .forward)]
        )
        descriptor.fetchLimit = limit * 2
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let filtered = fetched.filter {
            guard let ended = $0.endedAt else { return false }
            guard $0.totalSets > 0 else { return false }
            if let date { return ended > date }
            return true
        }
        return Array(filtered.prefix(limit))
    }

    func sessionExists(id: UUID) -> Bool {
        var descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 50
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        return fetched.contains { $0.id == id }
    }

    func deleteSession(_ session: WorkoutSession) {
        session.isHidden = true
        saveContext(reason: "deleteSession")
    }

    func importRemoteSession(
        session: RemoteSessionGraph.Session,
        exercises: [RemoteSessionGraph.Exercise],
        sets: [RemoteSessionGraph.Set]
    ) {
        guard sessionExists(id: session.id) == false else { return }
        let newSession = WorkoutSession(
            id: session.id,
            routineId: session.routine_id,
            routineTemplateId: session.routine_id,
            routineTitle: session.routine_title,
            startedAt: session.started_at,
            endedAt: session.ended_at,
            totalSets: session.total_sets,
            totalReps: session.total_reps,
            volumeKg: session.total_volume_kg,
            aiPostSummaryText: "",
            aiPostSummaryJSON: "",
            rating: nil,
            isCompleted: true,
            durationSeconds: session.ended_at != nil ? Int(session.ended_at!.timeIntervalSince(session.started_at)) : nil,
            aiPostSummaryGeneratedAt: nil,
            aiPostSummaryModel: nil,
            exercises: []
        )
        modelContext.insert(newSession)

        var exMap: [UUID: ExerciseLog] = [:]
        for ex in exercises {
            let exModel = ExerciseLog(id: ex.id, name: ex.exercise_name, orderIndex: ex.sort_index, session: newSession, sets: [])
            exMap[ex.id] = exModel
            newSession.exercises.append(exModel)
        }

        for set in sets {
            guard let exModel = exMap[set.exercise_log_id] else { continue }
            let setModel = SetLog(
                id: set.id,
                tag: set.tag ?? "S",
                weightKg: set.weight_kg,
                reps: set.reps,
                createdAt: set.created_at ?? session.started_at,
                exercise: exModel
            )
            exModel.sets.append(setModel)
        }

        if modelContext.hasChanges {
            try? modelContext.save()
        }
    }

    func recentSessions(limit: Int) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 2
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        return fetched
            .filter { $0.totalSets > 0 && $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    func sessions(on day: Date) -> [WorkoutSession] {
        let window = dayInterval(for: day)
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        return fetched.filter { session in
            guard session.totalSets > 0, session.isHidden == false, let ended = session.endedAt else { return false }
            return ended >= window.start && ended < window.end
        }
    }

    func activeDays(in month: Date) -> Set<Date> {
        let interval = monthInterval(containing: month)
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        let normalized = fetched.compactMap { session -> Date? in
            guard session.totalSets > 0, let ended = session.endedAt else { return nil }
            guard ended >= interval.start && ended < interval.end else { return nil }
            return startOfDay(ended)
        }
        return Set(normalized)
    }

    /// VISUAL TWEAK: Change volume calculation rules here if needed.
    private func computeTotals(for session: WorkoutSession) -> (sets: Int, reps: Int, volumeKg: Double) {
        let sessionID = session.id
        let fetchedExercises = (try? modelContext.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        // Fetch from context to ensure we count persisted exercises even if the session reference is stale.
        let exercisesForSession = fetchedExercises.filter { $0.session?.id == sessionID }
        let sourceExercises = exercisesForSession.isEmpty ? session.exercises : exercisesForSession

        var totalSets = 0
        var totalReps = 0
        var volume: Double = 0

        for exercise in sourceExercises {
            for set in exercise.sets {
                totalSets += 1
                totalReps += set.reps
                if let weight = set.weightKg {
                    volume += weight * Double(set.reps)
                }
            }
        }

        return (totalSets, totalReps, volume)
    }

    private func dayInterval(for date: Date) -> (start: Date, end: Date) {
        let start = startOfDay(date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private func monthInterval(containing date: Date) -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: comps) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private func existingActiveSession(routineId: UUID?, routineTitle: String) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { session in
            guard session.endedAt == nil else { return false }
            if let rid = routineId {
                return session.routineId == rid
            } else {
                return session.routineId == nil && session.routineTitle == routineTitle
            }
        }
    }

    /// Repairs sessions that have logged sets but zero totals (backfill).
    func repairZeroTotalSessionsIfNeeded() {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        var repaired = 0
        for session in sessions {
            let totals = computeTotals(for: session)
            if session.endedAt != nil && totals.sets > 0 && session.totalSets == 0 {
                session.totalSets = totals.sets
                session.totalReps = totals.reps
                session.volumeKg = totals.volumeKg
                repaired += 1
            }
        }
        if repaired > 0 {
            saveContext(reason: "repairZeroTotalSessionsIfNeeded")
            #if DEBUG
            print("[HISTORY] repaired \(repaired) sessions with missing totals")
            #endif
        }
    }

    private func resolvedSession(for id: UUID) -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.id == id }
    }

    func flush() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
            #if DEBUG
            print("[HISTORY] flush ok")
            #endif
        } catch {
            #if DEBUG
            print("[HISTORY][ERROR] flush failed: \(error)")
            #endif
        }
    }

    #if DEBUG
    func logMostRecentEndedSessionForDebug() {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        if let latest = sessions.first(where: { $0.endedAt != nil && $0.totalSets > 0 }) {
            let endedAt = latest.endedAt?.ISO8601Format() ?? "nil"
            print("[HISTORY] last ended session id=\(latest.id) endedAt=\(endedAt) sets=\(latest.totalSets) reps=\(latest.totalReps) volumeKg=\(String(format: "%.2f", latest.volumeKg))")
        } else {
            print("[HISTORY] no ended sessions found for persistence sanity check")
        }
    }
    #endif

    @discardableResult
    private func saveContext(reason: String) -> Bool {
        guard modelContext.hasChanges else { return true }
        do {
            try modelContext.save()
            return true
        } catch {
            #if DEBUG
            print("[HISTORY][ERROR] save failed (\(reason)): \(error)")
            #endif
            return false
        }
    }

    #if DEBUG
    private func logPersistenceCheck(for id: UUID) {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        if let match = try? modelContext.fetch(descriptor).first(where: { $0.id == id }) {
            let ended = match.endedAt?.ISO8601Format() ?? "nil"
            print("[HISTORY] verify session id=\(match.id) endedAt=\(ended) sets=\(match.totalSets) reps=\(match.totalReps) volumeKg=\(String(format: "%.2f", match.volumeKg))")
        } else {
            print("[HISTORY][ERROR] verify failed: session id=\(id) not found after save")
        }
    }
    #endif
}
