//
//  HistoryStore.swift
//  Atlas
//
//  Overview: Centralized SwiftData history writer/reader for sessions, sets, and calendar marks.
//

import Combine
import Foundation
import SwiftData

/// DEV MAP: History storage + queries live in `HistoryStore`.
@MainActor
final class HistoryStore: ObservableObject {
    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// DEV NOTE: ALL history writes go through HistoryStore so UI + AI always agree.
    func startSession(routineId: UUID?, routineTitle: String, exercises: [String], startedAt: Date = Date()) -> WorkoutSession {
        let session = WorkoutSession(
            routineId: routineId,
            routineTitle: routineTitle,
            startedAt: startedAt,
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
        return session
    }

    func addSet(session: WorkoutSession, exerciseName: String, orderIndex: Int, tag: SetTag, weightKg: Double?, reps: Int, createdAt: Date = Date()) {
        let exerciseLog = session.exercises.first(where: { $0.orderIndex == orderIndex && $0.name == exerciseName })
            ?? {
                let newExercise = ExerciseLog(name: exerciseName, orderIndex: orderIndex, session: session)
                session.exercises.append(newExercise)
                return newExercise
            }()

        let set = SetLog(tag: tag.rawValue, weightKg: weightKg, reps: reps, createdAt: createdAt, exercise: exerciseLog)
        exerciseLog.sets.append(set)

        saveContext()
    }

    /// Returns true if the session was stored, false if discarded for zero sets.
    func endSession(session: WorkoutSession, endedAt: Date = Date()) -> Bool {
        let totals = computeTotals(for: session)
        session.totalSets = totals.sets
        session.totalReps = totals.reps
        session.volumeKg = totals.volumeKg

        guard totals.sets > 0 else {
            modelContext.delete(session)
            saveContext()
            return false
        }

        session.isCompleted = true
        session.endedAt = endedAt
        saveContext()
        return true
    }

    func recentSessions(limit: Int) -> [WorkoutSession] {
        /// DEV NOTE: Placeholder in Pass 1 — real queries come in Pass 2.
        return []
    }

    func sessions(on day: Date) -> [WorkoutSession] {
        /// DEV NOTE: Placeholder in Pass 1 — real queries come in Pass 2.
        return []
    }

    func activeDays(in month: Date) -> Set<Date> {
        /// DEV NOTE: Placeholder in Pass 1 — real queries come in Pass 2.
        return []
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
