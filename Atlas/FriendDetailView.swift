import SwiftUI

struct FriendDetailView: View {
    let friend: AtlasFriend
    @EnvironmentObject private var authStore: AuthStore
    @StateObject private var model: FriendDetailModel

    private var title: String {
        if let username = friend.username, username.isEmpty == false {
            return "@\(username)"
        }
        return friend.email.isEmpty ? "Friend" : friend.email
    }

    private var friendUUID: UUID? { UUID(uuidString: friend.id) }

    init(friend: AtlasFriend) {
        self.friend = friend
        let fid = UUID(uuidString: friend.id) ?? UUID()
        _model = StateObject(wrappedValue: FriendDetailModel(friendId: fid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let error = model.errorMessage {
                    Text(error)
                        .appFont(.footnote)
                        .foregroundStyle(.red)
                }
                statsCard
                calendarCard
                sessionsList
            }
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.top, 20)
        }
        .refreshable {
            await refresh()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if model.isLoading {
                    ProgressView()
                        .tint(.primary)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadIfNeeded()
            }
        }
        .navigationTitle("Friend")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
            if let email = friend.email.isEmpty ? nil : friend.email {
                Text(email)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statsCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stats")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary)
                let stats = model.stats
                statRow(title: "Sessions", value: stats.map { "\($0.sessionsTotal)" } ?? "–")
                statRow(title: "Best volume (kg)", value: stats.map { String(format: "%.0f", $0.bestVolumeKg) } ?? "–")
                statRow(title: "Best sets", value: stats.map { "\($0.bestTotalSets)" } ?? "–")
                statRow(title: "Best reps", value: stats.map { "\($0.bestTotalReps)" } ?? "–")
                statRow(title: "Latest workout", value: stats?.latestEndedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "–")
            }
            .padding()
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.primary)
        }
    }

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            if model.sessionsForSelectedDay.isEmpty {
                Text(model.isLoading ? "Loading…" : "No sessions on this day.")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.sessionsForSelectedDay) { session in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.routineTitle.isEmpty ? "Workout" : session.routineTitle)
                                    .appFont(.body, weight: .semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(session.endedAt.formatted(date: .omitted, time: .shortened))
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Sets \(session.totalSets) · Reps \(session.totalReps) · Vol \(Int(session.volumeKg)) kg")
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        withAnimation(AppMotion.primary) {
                            model.selectDay(Calendar.current.date(byAdding: .month, value: -1, to: model.selectedDay) ?? model.selectedDay)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(monthTitle(model.selectedDay))
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        withAnimation(AppMotion.primary) {
                            model.selectDay(Calendar.current.date(byAdding: .month, value: 1, to: model.selectedDay) ?? model.selectedDay)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                weekHeader
                calendarGrid
            }
            .padding()
        }
    }

    private var weekHeader: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        return HStack {
            ForEach(symbols, id: \.self) { day in
                Text(day.uppercased())
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let days = daysInMonth(model.selectedDay)
        let counts = Dictionary(grouping: model.sessions) { Calendar.current.startOfDay(for: $0.endedAt) }.mapValues { $0.count }
        let firstWeekday = Calendar.current.component(.weekday, from: days.first ?? Date())
        let leading = (firstWeekday - Calendar.current.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<leading, id: \.self) { _ in
                Rectangle().fill(Color.clear).frame(height: 30)
            }
            ForEach(days, id: \.self) { day in
                VStack {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .appFont(.footnote)
                        .foregroundStyle(.primary)
                    if let count = counts[Calendar.current.startOfDay(for: day)], count > 0 {
                        Circle()
                            .fill(isSelected(day) ? Color.white : Color.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .overlay(
                                count > 1 ? Text("\(count)").appFont(.footnote).foregroundStyle(.primary) : nil
                            )
                            .padding(.top, 2)
                    } else {
                        Circle()
                            .fill(isSelected(day) ? Color.white.opacity(0.15) : Color.clear)
                            .frame(width: 6, height: 6)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.playLightTap()
                    model.selectDay(day)
                }
            }
        }
    }

    private func daysInMonth(_ date: Date) -> [Date] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        guard let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { day -> Date? in
            var comps = cal.dateComponents([.year, .month], from: start)
            comps.day = day
            return cal.date(from: comps)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        return fmt.string(from: date)
    }

    private func refresh() async {
        await loadIfNeeded(force: true)
    }

    private func loadIfNeeded(force: Bool = false) async {
        guard let id = friendUUID else {
            await MainActor.run { model.errorMessage = "Invalid friend." }
            return
        }
        guard let client = authStore.supabaseClient else {
            await MainActor.run { model.errorMessage = "Not signed in." }
            return
        }
        model.setService(FriendHistoryService(client: client))
        if force || model.sessions.isEmpty || model.stats == nil {
            await model.load()
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.current.isDate(model.selectedDay, inSameDayAs: day)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FriendDetailView(
            friend: AtlasFriend(
                id: UUID().uuidString,
                email: "friend@example.com",
                username: "friend",
                createdAt: Date()
            )
        )
        .environmentObject(FriendHistoryStore(authStore: AuthStore()))
    }
}
#endif
