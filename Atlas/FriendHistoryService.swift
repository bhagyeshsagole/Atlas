import Foundation
import Supabase

struct FriendHistoryService {
    let client: SupabaseClient

    func listSessions(targetUserId: UUID, from: Date?, to: Date?, limit: Int = 200) async throws -> [FriendWorkoutSessionSummary] {
        var params: [String: String] = [
            "target_user_id": targetUserId.uuidString,
            "limit_count": "\(limit)"
        ]
        if let from {
            params["from_ts"] = AtlasDateFormatters.iso8601WithFractionalSeconds.string(from: from)
        }
        if let to {
            params["to_ts"] = AtlasDateFormatters.iso8601WithFractionalSeconds.string(from: to)
        }

        let rows: [SessionRowRecord] = try await client
            .rpc("list_workout_sessions_for_user", params: params)
            .execute()
            .value

        let parsed = rows.compactMap { row -> FriendWorkoutSessionSummary? in
            guard let ended = parseDate(row.ended_at) else { return nil }
            return FriendWorkoutSessionSummary(
                id: row.session_id,
                routineTitle: row.routine_title,
                startedAt: parseDate(row.started_at),
                endedAt: ended,
                totalSets: row.total_sets,
                totalReps: row.total_reps,
                volumeKg: row.volume_kg
            )
        }
        let sorted = parsed.sorted { $0.endedAt > $1.endedAt }
        #if DEBUG
        print("[FRIEND_HISTORY] listSessions target=\(targetUserId) count=\(sorted.count)")
        #endif
        return sorted
    }

    func fetchStats(targetUserId: UUID) async throws -> FriendWorkoutStats {
        let params = ["target_user_id": targetUserId.uuidString]
        let rows: [StatsRowRecord] = try await client
            .rpc("workout_stats_for_user_row", params: params)
            .execute()
            .value
        guard let row = rows.first else {
            return FriendWorkoutStats(
                sessionsTotal: 0,
                bestVolumeKg: 0,
                bestTotalReps: 0,
                bestTotalSets: 0,
                latestEndedAt: nil,
                longestDurationSeconds: 0
            )
        }
        let stats = FriendWorkoutStats(
            sessionsTotal: row.sessions_total,
            bestVolumeKg: row.best_volume_kg,
            bestTotalReps: row.best_total_reps,
            bestTotalSets: row.best_total_sets,
            latestEndedAt: parseDate(row.latest_ended_at),
            longestDurationSeconds: row.longest_duration_seconds
        )
        #if DEBUG
        print("[FRIEND_HISTORY] stats target=\(targetUserId) sessionsTotal=\(stats.sessionsTotal)")
        #endif
        return stats
    }
}

// MARK: - Date parsing

private func parseDate(_ string: String?) -> Date? {
    guard let string else { return nil }
    if let date = AtlasDateFormatters.iso8601WithFractionalSeconds.date(from: string) {
        return date
    }
    let fallback = ISO8601DateFormatter()
    return fallback.date(from: string)
}
