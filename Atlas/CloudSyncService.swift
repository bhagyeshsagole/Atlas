import Foundation
import Supabase

struct WorkoutSessionCloudSummary: Sendable {
    let sessionId: UUID
    let routineTitle: String
    let startedAt: Date?
    let endedAt: Date
    let totalSets: Int
    let totalReps: Int
    let volumeKg: Double
}

struct CloudSyncService {
    let client: SupabaseClient
    private static let iso8601: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    func upsertWorkoutSessionSummary(_ summary: WorkoutSessionCloudSummary) async throws {
        var params: [String: String] = [
            "session_id": summary.sessionId.uuidString,
            "routine_title": summary.routineTitle,
            "ended_at": Self.iso8601.string(from: summary.endedAt),
            "total_sets": "\(summary.totalSets)",
            "total_reps": "\(summary.totalReps)",
            "volume_kg": "\(summary.volumeKg)"
        ]

        if let started = summary.startedAt {
            params["started_at"] = Self.iso8601.string(from: started)
        }

        _ = try await client
            .rpc("upsert_workout_session", params: params)
            .execute()
        #if DEBUG
        print("[CLOUDSYNC] upsert ok session=\(summary.sessionId)")
        #endif
    }

    // Bundle upload temporarily disabled; summary upsert remains the stable path.
}
