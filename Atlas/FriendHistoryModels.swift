import Foundation

struct FriendWorkoutSessionSummary: Identifiable, Sendable {
    let id: UUID
    let routineTitle: String
    let startedAt: Date?
    let endedAt: Date
    let totalSets: Int
    let totalReps: Int
    let volumeKg: Double
}

struct FriendWorkoutStats: Sendable {
    let sessionsTotal: Int
    let bestVolumeKg: Double
    let bestTotalReps: Int
    let bestTotalSets: Int
    let latestEndedAt: Date?
    let longestDurationSeconds: Double
}

// MARK: - Records

struct SessionRowRecord: Decodable {
    let session_id: UUID
    let user_id: UUID
    let routine_title: String
    let started_at: String?
    let ended_at: String
    let total_sets: Int
    let total_reps: Int
    let volume_kg: Double
}

struct StatsRowRecord: Decodable {
    let sessions_total: Int
    let best_volume_kg: Double
    let best_total_reps: Int
    let best_total_sets: Int
    let latest_ended_at: String?
    let longest_duration_seconds: Double
}
