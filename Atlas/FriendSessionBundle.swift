import Foundation

/// Raw RPC response models for get_workout_session_bundle. Timestamps remain String so we can parse safely later.
struct FriendSessionBundleRow: Decodable {
    let bundle: FriendSessionBundle
}

struct FriendSessionBundle: Decodable {
    let session: FriendSessionSession
    let exercises: [FriendSessionExercise]
    let sets: [FriendSessionSet]
}

struct FriendSessionSession: Decodable {
    let user_id: String?
    let session_id: String
    let routine_title: String
    let started_at: String?
    let ended_at: String?
    let total_sets: Int
    let total_reps: Int
    let volume_kg: Double
}

struct FriendSessionExercise: Decodable, Identifiable {
    var id: String { exercise_id }
    let exercise_id: String
    let session_id: String?
    let name: String
    let order_index: Int
}

struct FriendSessionSet: Decodable, Identifiable {
    var id: String { set_id }
    let set_id: String
    let exercise_id: String
    let session_id: String?
    let order_index: Int
    let reps: Int
    let weight_kg: Double
    let is_warmup: Bool
}
