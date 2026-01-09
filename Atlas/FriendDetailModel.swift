import Foundation
import Combine

final class FriendDetailModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var stats: FriendWorkoutStats?
    @Published var sessions: [FriendWorkoutSessionSummary] = []
    @Published var selectedDay: Date = Date()
    @Published var sessionsForSelectedDay: [FriendWorkoutSessionSummary] = []

    private var service: FriendHistoryService?
    private let friendId: UUID

    init(friendId: UUID, service: FriendHistoryService? = nil) {
        self.friendId = friendId
        self.service = service
    }

    func setService(_ service: FriendHistoryService?) {
        self.service = service
    }

    func load() async {
        guard let service else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let sessionsTask = service.listSessions(targetUserId: friendId, from: nil, to: nil, limit: 200)
            async let statsTask = service.fetchStats(targetUserId: friendId)
            let fetchedSessions = try await sessionsTask
            let fetchedStats = try await statsTask
            sessions = fetchedSessions.sorted { $0.endedAt > $1.endedAt }
            stats = fetchedStats
            computeDerived()
        } catch {
            errorMessage = friendlyError(from: error)
        }
    }

    func selectDay(_ day: Date) {
        selectedDay = Calendar.current.startOfDay(for: day)
        computeDerived()
    }

    private func computeDerived() {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.endedAt) }
        if grouped[selectedDay] == nil, let mostRecent = sessions.first?.endedAt {
            selectedDay = cal.startOfDay(for: mostRecent)
        }
        sessionsForSelectedDay = grouped[selectedDay]?.sorted(by: { $0.endedAt > $1.endedAt }) ?? []
    }

    private func friendlyError(from error: Error) -> String {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("not friends") || lower.contains("not authorized") {
            return "You can’t view this user’s workouts."
        }
        return "Couldn’t load workouts. Pull to refresh."
    }
}
