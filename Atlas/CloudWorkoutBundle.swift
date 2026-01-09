import Foundation

struct CloudExerciseRow: Encodable, Sendable {
    let exercise_id: UUID
    let name: String
    let order_index: Int
}

struct CloudSetRow: Encodable, Sendable {
    let set_id: UUID
    let exercise_id: UUID
    let order_index: Int
    let reps: Int
    let weight_kg: Double
    let is_warmup: Bool
}

struct CloudWorkoutSessionBundle: Encodable, Sendable {
    let user_id: UUID
    let session_id: UUID
    let routine_title: String
    let started_at: Date?
    let ended_at: Date
    let total_sets: Int
    let total_reps: Int
    let volume_kg: Double
    let exercises: [CloudExerciseRow]
    let sets: [CloudSetRow]
}
