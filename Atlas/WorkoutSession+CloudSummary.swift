import Foundation

extension WorkoutSession {
    var cloudSummary: WorkoutSessionCloudSummary? {
        guard let endedAt = endedAt, totalSets > 0 else { return nil }
        return WorkoutSessionCloudSummary(
            sessionId: id,
            routineTitle: routineTitle.isEmpty ? "Untitled" : routineTitle,
            startedAt: startedAt,
            endedAt: endedAt,
            totalSets: totalSets,
            totalReps: totalReps,
            volumeKg: volumeKg
        )
    }
}
