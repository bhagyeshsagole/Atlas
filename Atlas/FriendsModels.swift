import Foundation

struct AtlasFriend: Identifiable, Hashable {
    let id: String
    let email: String
    let username: String?
    let createdAt: Date?
}

struct AtlasFriendRequest: Identifiable, Hashable {
    let id: String
    let fromUser: String
    let toUser: String
    let fromEmail: String?
    let toEmail: String?
    let fromUsername: String?
    let toUsername: String?
    let status: String
    let createdAt: Date?
}
