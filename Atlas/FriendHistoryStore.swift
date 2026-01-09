import Foundation
import Supabase
import SwiftUI
import Combine

@MainActor
final class FriendHistoryStore: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sessions: [FriendWorkoutSessionSummary] = []
    @Published var stats: FriendWorkoutStats?
    @Published var selectedMonth: Date = Date()
    @Published var selectedDay: Date?

    private let authStore: AuthStore
    private let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(authStore: AuthStore) {
        self.authStore = authStore
    }

    func load(friendUserId: UUID) async {
        selectedMonth = startOfMonth(selectedMonth)
        await refresh(friendId: friendUserId)
    }

    func refresh(friendId: UUID) async {
        guard authStore.isAuthenticated, let client = authStore.supabaseClient else {
            errorMessage = "Sign in to load history."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let service = FriendHistoryService(client: client)
        do {
            async let sessionsTask = service.listSessions(targetUserId: friendId, from: nil, to: nil, limit: 200)
            async let statsTask = service.fetchStats(targetUserId: friendId)
            let fetchedSessions = try await sessionsTask
            let fetchedStats = try await statsTask
            await MainActor.run {
                sessions = fetchedSessions.sorted { $0.endedAt > $1.endedAt }
                stats = fetchedStats
                selectedDay = nil
                errorMessage = nil
            }
        } catch {
            errorMessage = friendlyError(from: error)
            #if DEBUG
            print("[FRIEND_HISTORY][ERROR] user=\(friendId) error=\(error)")
            #endif
        }
    }

    func clear() {
        sessions = []
        stats = nil
        errorMessage = nil
    }

    func sessionsForMonth(_ month: Date) -> [FriendWorkoutSessionSummary] {
        let start = startOfMonth(month)
        let end = monthEnd(start)
        return sessions.filter { session in
            session.endedAt >= start && session.endedAt < end
        }
    }

    func workoutCountByDay(for month: Date) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        let cal = Calendar.current
        for session in sessionsForMonth(month) {
            let day = cal.startOfDay(for: session.endedAt)
            counts[day, default: 0] += 1
        }
        return counts
    }

    var workoutDays: Set<String> {
        Set(sessions.map { dayKeyFormatter.string(from: $0.endedAt) })
    }

    func sessionsForSelectedDay() -> [FriendWorkoutSessionSummary] {
        guard let selectedDay else { return sessions }
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.endedAt, inSameDayAs: selectedDay) }
    }

    private func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func monthEnd(_ start: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
    }

    private func friendlyError(from error: Error) -> String {
        let lower = error.localizedDescription.lowercased()
        if lower.contains("not friends") || lower.contains("not authorized") {
            return "You can’t view this user’s workouts."
        }
        return "Couldn’t load workouts. Pull to refresh."
    }
}
