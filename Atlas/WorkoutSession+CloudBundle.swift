import Foundation

extension WorkoutSession {
    func cloudBundle(userId: UUID) -> CloudWorkoutSessionBundle? {
        guard let endedAt = endedAt, totalSets > 0 else { return nil }
        let exercises = exercises.sorted { $0.orderIndex < $1.orderIndex }.map { ex in
            CloudExerciseRow(
                exercise_id: ex.id,
                name: ex.name,
                order_index: ex.orderIndex
            )
        }
        let sets = exercises
        let flatSets: [CloudSetRow] = exercises.enumerated().flatMap { idx, exRow in
            let exerciseModel = self.exercises.first { $0.id == exRow.exercise_id }
            let setRows = exerciseModel?.sets.enumerated().map { setIdx, set in
                CloudSetRow(
                    set_id: set.id,
                    exercise_id: exRow.exercise_id,
                    order_index: setIdx,
                    reps: set.reps,
                    weight_kg: set.weightKg ?? 0,
                    is_warmup: set.tagRaw.uppercased() == "W"
                )
            } ?? []
            return setRows
        }

        return CloudWorkoutSessionBundle(
            user_id: userId,
            session_id: id,
            routine_title: routineTitle.isEmpty ? "Untitled" : routineTitle,
            started_at: startedAt,
            ended_at: endedAt,
            total_sets: totalSets,
            total_reps: totalReps,
            volume_kg: volumeKg,
            exercises: exercises,
            sets: flatSets
        )
    }
}
