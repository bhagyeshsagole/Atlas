import Foundation

struct FriendHistoryRPCListSessionsParams: Encodable, Sendable {
    let target_user_id: String
    let from_ts: Date?
    let to_ts: Date?
    let limit_count: Int
}

struct FriendHistoryRPCStatsParams: Encodable, Sendable {
    let target_user_id: String
}
