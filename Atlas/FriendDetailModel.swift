import Foundation
import Combine

final class FriendDetailModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var stats: FriendWorkoutStats?
    @Published var sessions: [FriendWorkoutSessionSummary] = []
    @Published var selectedMonth: Date
    @Published var selectedDay: Date?
    @Published var sessionsForSelectedDay: [FriendWorkoutSessionSummary] = []
    @Published var daysWithSessions: Set<Date> = []

    private var service: FriendHistoryService?
    private let friendId: UUID

    init(friendId: UUID, service: FriendHistoryService? = nil) {
        self.friendId = friendId
        self.service = service
        let now = Date()
        self.selectedMonth = Self.startOfMonth(now)
        self.selectedDay = nil
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
            let range = monthRange(for: selectedMonth)
            async let sessionsTask = service.listSessions(targetUserId: friendId, from: range.start, to: range.end, limit: 200)
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

    func goPrevMonth() async {
        let prev = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        selectedMonth = Self.startOfMonth(prev)
        await refresh()
    }

    func goNextMonth() async {
        let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        selectedMonth = Self.startOfMonth(next)
        await refresh()
    }

    private func computeDerived() {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.endedAt) }
        daysWithSessions = Set(grouped.keys)
        if let sel = selectedDay, grouped[sel] != nil {
            // keep selection
        } else if let mostRecent = sessions.first?.endedAt {
            selectedDay = cal.startOfDay(for: mostRecent)
        } else {
            selectedDay = nil
        }
        if let sel = selectedDay {
            sessionsForSelectedDay = grouped[sel]?.sorted(by: { $0.endedAt > $1.endedAt }) ?? []
        } else {
            sessionsForSelectedDay = []
        }
    }

    private func friendlyError(from error: Error) -> String {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("not friends") || lower.contains("not authorized") {
            return "You can’t view this user’s workouts."
        }
        return "Couldn’t load workouts. Pull to refresh."
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func monthRange(for date: Date) -> (start: Date, end: Date) {
        let start = Self.startOfMonth(date)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }
}
