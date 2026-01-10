import Foundation
import Combine

final class FriendDetailModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var friendStats: FriendWorkoutStats?
    @Published var sessions: [FriendWorkoutSessionSummary] = []

    private var service: FriendHistoryService?
    private let friendId: UUID

    init(friendId: UUID, service: FriendHistoryService? = nil) {
        self.friendId = friendId
        self.service = service
    }

    func setService(_ service: FriendHistoryService?) {
        self.service = service
    }

    func refresh() async {
        guard let service else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Pull a generous range so Week/Month/All-time can be derived locally.
            async let sessionsTask = service.listSessions(targetUserId: friendId, from: nil, to: nil, limit: 200)
            async let statsTask = service.fetchStats(targetUserId: friendId)
            let fetchedSessions = try await sessionsTask
            let fetchedStats = try await statsTask
            sessions = fetchedSessions.sorted { $0.endedAt > $1.endedAt }
            friendStats = fetchedStats
        } catch {
            errorMessage = friendlyError(from: error)
        }
    }

    private func friendlyError(from error: Error) -> String {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("not friends") || lower.contains("not authorized") {
            return "You can’t view this user’s workouts."
        }
        return "Couldn’t load workouts. Pull to refresh."
    }
}
