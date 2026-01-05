//
//  HistoryStore.swift
//  Atlas
//
//  Overview: Centralized SwiftData history writer/reader for sessions, sets, and calendar marks.
//

import Foundation
import Combine
import SwiftData

/// DEV MAP: History writes/reads live here (queries, discard rules, calendar data).
/// DEV NOTE: ALL history writes go through HistoryStore so UI + AI always agree.
/// DEV NOTE: Queries avoid #Predicate macros to prevent SwiftData macro compiler issues.
@MainActor
final class HistoryStore: ObservableObject {
    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startSession(routineId: UUID?, routineTitle: String, exercises: [String]) -> WorkoutSession {
        // Re-entrancy guard: reuse any active draft for the same routine to avoid duplicate starts.
        if let active = existingActiveSession(routineId: routineId, routineTitle: routineTitle) {
            return active
        }

        let session = WorkoutSession(
            routineId: routineId,
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
        saveContext()

        #if DEBUG
        let exerciseList = exercises.joined(separator: ", ")
        print("[HISTORY] start session id=\(session.id) routine=\(routineTitle) exercises=\(exerciseList)")
        #endif

        return session
    }

    func addSet(session: WorkoutSession, exerciseName: String, orderIndex: Int, tag: SetTag, weightKg: Double?, reps: Int) {
        let exerciseLog = session.exercises.first(where: { $0.orderIndex == orderIndex })
            ?? session.exercises.first(where: { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame })
            ?? {
                let newExercise = ExerciseLog(name: exerciseName, orderIndex: orderIndex, session: session)
                session.exercises.append(newExercise)
                return newExercise
            }()

        let set = SetLog(tag: tag.rawValue, weightKg: weightKg, reps: reps, createdAt: Date(), exercise: exerciseLog)
        exerciseLog.sets.append(set)

        saveContext()

        #if DEBUG
        let weightDisplay = weightKg.map { String(format: "%.2f", $0) } ?? "nil"
        print("[HISTORY] addSet ex=\(exerciseName) tag=\(tag.rawValue) kg=\(weightDisplay) reps=\(reps)")
        #endif
    }

    /// Returns true if the session was stored, false if discarded for zero sets.
    func endSession(session: WorkoutSession) -> Bool {
        let totals = computeTotals(for: session)

        session.totalSets = totals.sets
        session.totalReps = totals.reps
        session.volumeKg = totals.volumeKg

        guard totals.sets > 0 else {
            modelContext.delete(session)
            saveContext()
            return false
        }

        session.endedAt = Date()
        session.isCompleted = true

        saveContext()

        #if DEBUG
        print("[HISTORY] end session id=\(session.id) stored=true sets=\(totals.sets) volumeKg=\(String(format: "%.2f", totals.volumeKg))")
        #endif

        return true
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
            guard session.totalSets > 0, let ended = session.endedAt else { return false }
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
        var totalSets = 0
        var totalReps = 0
        var volume: Double = 0

        for exercise in session.exercises {
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

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[HISTORY][ERROR] save failed: \(error)")
            #endif
        }
    }
}
