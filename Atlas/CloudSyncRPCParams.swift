import Foundation

struct UpsertWorkoutSessionParams: Encodable, Sendable {
    let session_id: UUID
    let routine_title: String
    let started_at: Date?
    let ended_at: Date
    let total_sets: Int
    let total_reps: Int
    let volume_kg: Double
}
