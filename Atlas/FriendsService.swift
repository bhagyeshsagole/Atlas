import Foundation
import Supabase

enum FriendsServiceError: Error {
    case invalidUsername
    case invalidEmail
    case profileNotFound
    case cannotFriendSelf
    case duplicateRequest
    case alreadyFriends
    case unauthorized
    case backend(String)
}

struct FriendsService {
    private let client: SupabaseClient
    private static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()
    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Public API

    func sendFriendRequest(input: String) async throws {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard normalized.isEmpty == false else {
            throw FriendsServiceError.invalidUsername
        }
        if normalized.contains("@") {
            try await sendByEmail(normalized)
        } else {
            try await sendByUsername(normalized)
        }
    }

    func fetchIncomingRequests(for userId: UUID) async throws -> [AtlasFriendRequest] {
        let requests: [FriendRequestRecord] = try await fetchRequests(filterColumn: "to_user", userId: userId)
        let enriched = try await attachEmails(to: requests)
        return enriched.filter { $0.status == "pending" && $0.toUser == userId.uuidString }
    }

    func fetchOutgoingRequests(for userId: UUID) async throws -> [AtlasFriendRequest] {
        let requests: [FriendRequestRecord] = try await fetchRequests(filterColumn: "from_user", userId: userId)
        let enriched = try await attachEmails(to: requests)
        return enriched.filter { $0.status == "pending" && $0.fromUser == userId.uuidString }
    }

    func acceptRequest(requestId: UUID) async throws {
        try await respondToRequest(requestId: requestId, decision: "accepted")
    }

    func declineRequest(requestId: UUID) async throws {
        try await respondToRequest(requestId: requestId, decision: "declined")
    }

    func removeFriend(friendId: UUID) async throws {
        do {
            _ = try await client
                .rpc("remove_friend", params: ["friend_id": friendId])
                .execute()
            #if DEBUG
            print("[FRIENDS] rpc=remove_friend ok id=\(friendId)")
            #endif
        } catch {
            throw mapRemoveError(error)
        }
    }

    func fetchFriends(for userId: UUID) async throws -> [AtlasFriend] {
        let response: [FriendEdgeRecord] = try await client
            .from("friends")
            .select("user_a,user_b,created_at")
            .or("user_a.eq.\(userId.uuidString),user_b.eq.\(userId.uuidString)")
            .execute()
            .value

        let otherIds: [UUID] = response.compactMap { edge in
            if edge.user_a == userId { return edge.user_b }
            if edge.user_b == userId { return edge.user_a }
            return nil
        }
        guard otherIds.isEmpty == false else { return [] }

        let profiles = try await fetchProfiles(for: Set(otherIds))
        let friendRows: [AtlasFriend] = response.compactMap { edge in
            let otherId: UUID
            if edge.user_a == userId {
                otherId = edge.user_b
            } else if edge.user_b == userId {
                otherId = edge.user_a
            } else {
                return nil
            }
            return AtlasFriend(
                id: otherId.uuidString,
                email: profiles[otherId]?.email ?? "Unknown",
                username: profiles[otherId]?.username,
                createdAt: parseDate(edge.created_at)
            )
        }
        return friendRows.sorted { ($0.username ?? $0.email).lowercased() < ($1.username ?? $1.email).lowercased() }
    }

    // MARK: - Private helpers

    private func fetchRequests(filterColumn: String, userId: UUID) async throws -> [FriendRequestRecord] {
        let response: [FriendRequestRecord] = try await client
            .from("friend_requests")
            .select("id,from_user,to_user,status,created_at")
            .eq(filterColumn, value: userId)
            .execute()
            .value

        return response
    }

    private func attachEmails(to requests: [FriendRequestRecord]) async throws -> [AtlasFriendRequest] {
        guard requests.isEmpty == false else { return [] }

        var ids: Set<UUID> = []
        requests.forEach {
            ids.insert($0.from_user)
            ids.insert($0.to_user)
        }

        let profiles = try await fetchProfiles(for: ids)

        return requests.map { req in
            AtlasFriendRequest(
                id: req.id.uuidString,
                fromUser: req.from_user.uuidString,
                toUser: req.to_user.uuidString,
                fromEmail: profiles[req.from_user]?.email,
                toEmail: profiles[req.to_user]?.email,
                fromUsername: profiles[req.from_user]?.username,
                toUsername: profiles[req.to_user]?.username,
                status: req.status,
                createdAt: parseDate(req.created_at)
            )
        }
    }

    private func fetchProfiles(for ids: Set<UUID>) async throws -> [UUID: ProfileLookupRow] {
        guard ids.isEmpty == false else { return [:] }
        let limited = Array(ids.prefix(50))
        let response: [ProfileLookupRow] = try await client
            .rpc("profiles_public_lookup", params: ["user_ids": limited])
            .execute()
            .value

        var map: [UUID: ProfileLookupRow] = [:]
        response.forEach { row in
            map[row.id] = row
        }
        return map
    }

    private func respondToRequest(requestId: UUID, decision: String) async throws {
        do {
            _ = try await client
                .rpc("respond_friend_request", params: ["request_id": requestId.uuidString, "decision": decision])
                .execute()
            #if DEBUG
            print("[FRIENDS] rpc=respond_friend_request decision=\(decision) ok")
            #endif
        } catch {
            throw mapRespondError(error)
        }
    }

    private func isDuplicate(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("duplicate") || message.contains("unique") || message.contains("already exists")
    }

    private func mapSendError(_ error: Error) -> FriendsServiceError {
        let message = error.localizedDescription.lowercased()
        if message.contains("profile found") || message.contains("no profile") || message.contains("not found") {
            return .profileNotFound
        }
        if message.contains("yourself") || message.contains("self") {
            return .cannotFriendSelf
        }
        if message.contains("pending") || message.contains("duplicate") || message.contains("already exists") {
            return .duplicateRequest
        }
        if message.contains("already friends") {
            return .alreadyFriends
        }
        if message.contains("not authorized") || message.contains("permission") {
            return .unauthorized
        }
        #if DEBUG
        print("[FRIENDS][DECODE] rpc error: \(error)")
        #endif
        return .backend(error.localizedDescription)
    }

    private func mapRespondError(_ error: Error) -> FriendsServiceError {
        let message = error.localizedDescription.lowercased()
        if message.contains("not found") {
            return .backend("Request not found.")
        }
        if message.contains("recipient") || message.contains("respond") {
            return .unauthorized
        }
        if message.contains("already") && message.contains("handled") {
            return .duplicateRequest
        }
        return .backend(error.localizedDescription)
    }

    private func mapRemoveError(_ error: Error) -> FriendsServiceError {
        let message = error.localizedDescription.lowercased()
        if message.contains("not authorized") || message.contains("permission") {
            return .unauthorized
        }
        if message.contains("not found") {
            return .backend("Friend not found.")
        }
        return .backend(error.localizedDescription)
    }
}

// MARK: - Records

private struct FriendRequestRecord: Decodable {
    let id: UUID
    let from_user: UUID
    let to_user: UUID
    let status: String
    let created_at: String?
}

private struct FriendEdgeRecord: Decodable {
    let user_a: UUID
    let user_b: UUID
    let created_at: String?
}

private struct ProfileLookupRow: Decodable {
    let id: UUID
    let email: String?
    let username: String?
}

// MARK: - Helpers

private extension FriendsService {
    enum FriendsRPCDecodeError: Error {
        case unexpectedResponse
    }

    func decodeUUID(from data: Data) throws -> UUID {
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        func uuid(from any: Any?) -> UUID? {
            if let u = any as? UUID { return u }
            if let s = any as? String { return UUID(uuidString: s) }
            return nil
        }

        if let direct = uuid(from: json) { return direct }

        if let array = json as? [Any], let first = array.first {
            if let u = uuid(from: first) { return u }
            if let dict = first as? [String: Any] {
                if let u = uuid(from: dict["request_id"]) { return u }
                if let u = uuid(from: dict["id"]) { return u }
                if let u = uuid(from: dict["send_friend_request"]) { return u }
                if let u = uuid(from: dict["send_friend_request_to_username"]) { return u }
                if let u = uuid(from: dict.values.first) { return u }
            }
        }

        if let dict = json as? [String: Any] {
            if let u = uuid(from: dict["request_id"]) { return u }
            if let u = uuid(from: dict["id"]) { return u }
            if let u = uuid(from: dict["send_friend_request"]) { return u }
            if let u = uuid(from: dict["send_friend_request_to_username"]) { return u }
            if let u = uuid(from: dict.values.first) { return u }
        }

        throw FriendsRPCDecodeError.unexpectedResponse
    }

    func sendByUsername(_ username: String) async throws {
        do {
            let response = try await client
                .rpc("send_friend_request_to_username", params: ["to_username": username])
                .execute()
            let requestId = try decodeUUID(from: response.data)
            #if DEBUG
            print("[FRIENDS] rpc=send_friend_request_to_username ok id=\(requestId)")
            #endif
        } catch {
            throw mapSendError(error)
        }
    }

    func sendByEmail(_ email: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { throw FriendsServiceError.invalidEmail }
        do {
            let response = try await client
                .rpc("send_friend_request", params: ["to_email": normalized])
                .execute()
            let requestId = try decodeUUID(from: response.data)
            #if DEBUG
            print("[FRIENDS] rpc=send_friend_request ok id=\(requestId)")
            #endif
        } catch {
            throw mapSendError(error)
        }
    }

    func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = FriendsService.isoFormatter.date(from: string) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: string)
    }
}
