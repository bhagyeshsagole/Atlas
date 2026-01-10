import SwiftUI
import SwiftData

struct FriendDetailView: View {
    let friend: AtlasFriend
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var friendsStore: FriendsStore
    @StateObject private var model: FriendDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirm = false
    @State private var removalSuccessMessage: String?
    @StateObject private var myStatsStore = StatsStore()
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var mySessions: [WorkoutSession]
    @State private var selectedRange: StatsLens = .week

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
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Picker("Range", selection: $selectedRange) {
                        ForEach(StatsLens.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    if let error = model.errorMessage {
                        Text(error)
                            .appFont(.footnote)
                            .foregroundStyle(.red)
                    } else if let success = removalSuccessMessage {
                        Text(success)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.green)
                    }

                    comparisonCards

                    removeFriendButton
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
            }
            .scrollIndicators(.hidden)
            .disabled(showRemoveConfirm)

            if showRemoveConfirm {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        Haptics.playLightTap()
                        withAnimation(AppMotion.primary) { showRemoveConfirm = false }
                    }
                VStack {
                    Spacer()
                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        VStack(alignment: .center, spacing: 12) {
                            Text("Remove friend?")
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.primary)
                            Text("This removes you from each other’s friends list.")
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Button {
                                    Haptics.playLightTap()
                                    withAnimation(AppMotion.primary) { showRemoveConfirm = false }
                                } label: {
                                    Text("Cancel")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PressableGlassButtonStyle())

                                Button(role: .destructive) {
                                    Haptics.playMediumImpact()
                                    Task { await removeFriend() }
                                } label: {
                                    Text("Remove")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PressableGlassButtonStyle())
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
            myStatsStore.updateSessions(Array(mySessions))
        }
        .onChange(of: mySessions) { _, newValue in
            myStatsStore.updateSessions(Array(newValue))
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

    private var comparisonCards: some View {
        let myMetrics = myStatsStore.metrics(for: selectedRange)
        let friendMetrics = metricsForFriend(range: selectedRange)
        return VStack(alignment: .leading, spacing: 16) {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscle Coverage")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    ForEach(MuscleGroup.allCases) { bucket in
                        HStack(spacing: 10) {
                            Text(bucket.displayName)
                                .appFont(.footnote, weight: .semibold)
                                .foregroundStyle(.primary)
                                .frame(width: 80, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                coverageRow(label: "You", score: myMetrics.muscle[bucket]?.progress01 ?? 0, display: myMetrics.muscle[bucket]?.score0to10 ?? 0)
                                coverageRow(label: "Friend", score: friendMetrics.muscle[bucket]?.progress01 ?? 0, display: friendMetrics.muscle[bucket]?.score0to10 ?? 0)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Workload")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    workloadRow(label: "You", metrics: myMetrics.workload)
                    workloadRow(label: "Friend", metrics: friendMetrics.workload)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coach Insights")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    coachRow(title: "You", summary: myMetrics.coach)
                    coachRow(title: "Friend", summary: friendMetrics.coach, isFriend: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func coverageRow(label: String, score: Double, display: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(display) / 10")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.primary)
            }
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
                .frame(height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: CGFloat(max(0, min(1, score)) * 180), alignment: .leading),
                    alignment: .leading
                )
        }
    }

    private func workloadRow(label: String, metrics: WorkloadSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            HStack {
                statColumn(title: "Volume", value: String(format: "%.0f kg", metrics.volume))
                Spacer()
                statColumn(title: "Sets", value: "\(metrics.sets)")
                Spacer()
                statColumn(title: "Reps", value: "\(metrics.reps)")
            }
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
        }
    }

    private func coachRow(title: String, summary: CoachSummary, isFriend: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            Text("Streak: \(summary.streakWeeks) wks")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            Text(summary.next.isEmpty ? (isFriend ? "No data yet" : "Keep going") : summary.next)
                .appFont(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var removeFriendButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            if authStore.isReadyForFriends {
                AtlasPillButton("Remove Friend") {
                    Haptics.playLightTap()
                    withAnimation(AppMotion.primary) {
                        showRemoveConfirm = true
                    }
                }
                .tint(.red)
            }
        }
    }

    private func removeFriend() async {
        let success = await friendsStore.remove(friendIdString: friend.id)
        if success {
            await MainActor.run {
                removalSuccessMessage = "Friend removed."
                withAnimation(AppMotion.primary) {
                    showRemoveConfirm = false
                }
                dismiss()
            }
        } else {
            await MainActor.run {
                removalSuccessMessage = nil
                model.errorMessage = friendsStore.lastErrorMessage ?? "Could not remove friend."
            }
        }
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
        if force || model.sessions.isEmpty || model.friendStats == nil {
            await model.refresh()
        }
        if model.friendStats == nil {
            await model.refresh()
        }
    }

    private func metricsForFriend(range: StatsLens) -> StatsMetrics {
        let filtered = filterFriendSessions(for: range, sessions: model.sessions)
        var volume: Double = 0
        var sets: Int = 0
        var reps: Int = 0
        for session in filtered {
            volume += session.volumeKg
            sets += session.totalSets
            reps += session.totalReps
        }
        let workload = WorkloadSummary(volume: volume, sets: sets, reps: reps)
        let emptyMuscle = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map {
            ($0, BucketScore(bucket: $0, score0to10: 0, progress01: 0, coveredTags: [], missingTags: [], hardSets: 0, trainingDays: 0, reasons: ["No exercise breakdown available"], suggestions: []))
        })
        let coach = CoachSummary(streakWeeks: filtered.isEmpty ? 0 : 1, next: filtered.isEmpty ? "No data yet" : "Invite to log more", reason: "")
        return StatsMetrics(lens: range, muscle: emptyMuscle, workload: workload, coach: coach)
    }

    private func filterFriendSessions(for range: StatsLens, sessions: [FriendWorkoutSessionSummary]) -> [FriendWorkoutSessionSummary] {
        let now = Date()
        let start: Date?
        switch range {
        case .week:
            start = Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            start = Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .all:
            start = nil
        }
        return sessions.filter { session in
            if let start {
                return session.endedAt >= start && session.endedAt <= now
            }
            return true
        }
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
