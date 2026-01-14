import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var friendsStore: FriendsStore
    @State private var usernameInput: String = ""
    @State private var leaderboardMetric: LeaderboardMetric = .streak
    private let primaryColor = Color.white
    private let secondaryColor = Color.white.opacity(0.72)

    enum LeaderboardMetric: String, CaseIterable, Identifiable {
        case streak = "Streak"
        case weeklyVolume = "Volume"
        case sessions = "Sessions"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    header
                    if authStore.isReadyForFriends {
                        statusMessages
                        addFriendCard
                        friendsCard
                        requestsCard
                        leaderboardCard
                    } else {
                        unauthenticatedCard
                    }
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .tint(primaryColor)
        .atlasBackground()
        .atlasBackgroundTheme(.friends)
        .task {
            await refreshIfReady()
        }
        .refreshable {
            await refreshIfReady()
        }
        .onChange(of: authStore.isReadyForFriends) { _, isReady in
            if isReady {
                Task { await friendsStore.refreshAll() }
            } else {
                setNotReadyMessage()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Friends")
                .appFont(.title, weight: .semibold)
                .foregroundStyle(primaryColor)
            Spacer()
            if friendsStore.isLoading {
                ProgressView()
                    .tint(primaryColor)
            } else {
                AtlasHeaderIconButton(systemName: "arrow.clockwise", isGlassBackplate: true) {
                    Haptics.playLightTap()
                    Task { await refreshIfReady() }
                }
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let success = friendsStore.successMessage {
            Text(success)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.green)
        } else if let message = friendsStore.lastErrorMessage ?? friendsStore.errorMessage ?? friendsStore.uiError {
            Text(message)
                .appFont(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var addFriendCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add friend")
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(primaryColor)
                    TextField("Username or email", text: $usernameInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .foregroundStyle(primaryColor)
                        .tint(primaryColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                }
                AtlasPillButton("Send request") {
                    sendRequest()
                }
                .frame(minWidth: 120)
                .tint(.primary)
                .disabled(friendsStore.isLoading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var requestsCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Requests")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(primaryColor)
                if friendsStore.incomingRequests.isEmpty && friendsStore.outgoingRequests.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("No requests")
                            .appFont(.footnote)
                            .foregroundStyle(secondaryColor)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(friendsStore.incomingRequests) { request in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.fromUsername.map { "@\($0)" } ?? (request.fromEmail ?? "Unknown"))
                                        .appFont(.body, weight: .semibold)
                                        .foregroundStyle(primaryColor)
                                    if let date = request.createdAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .appFont(.footnote)
                                            .foregroundStyle(secondaryColor)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button {
                                        Haptics.playLightTap()
                                        Task { await friendsStore.accept(requestIdString: request.id) }
                                    } label: {
                                        Text("Accept")
                                    }
                                    .buttonStyle(PressableGlassButtonStyle())
                                    .disabled(friendsStore.isLoading)

                                    Button {
                                        Haptics.playLightTap()
                                        Task { await friendsStore.decline(requestIdString: request.id) }
                                    } label: {
                                        Text("Decline")
                                    }
                                    .buttonStyle(PressableGlassButtonStyle())
                                    .disabled(friendsStore.isLoading)
                                }
                            }
                        }

                        ForEach(friendsStore.outgoingRequests) { request in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.toUsername.map { "@\($0)" } ?? (request.toEmail ?? "Unknown"))
                                        .appFont(.body, weight: .semibold)
                                        .foregroundStyle(primaryColor)
                                    if let date = request.createdAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .appFont(.footnote)
                                            .foregroundStyle(secondaryColor)
                                    }
                                }
                                Spacer()
                                Text("Pending")
                                    .appFont(.footnote, weight: .semibold)
                                    .foregroundStyle(secondaryColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private var friendsCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(primaryColor)
                if friendsStore.friends.isEmpty {
                    Text("No friends yet")
                        .appFont(.footnote)
                        .foregroundStyle(secondaryColor)
                } else {
                    VStack(spacing: 10) {
                        ForEach(friendsStore.friends) { friend in
                            NavigationLink(destination: FriendDetailView(friend: friend)) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Text(initials(for: friend))
                                                .appFont(.body, weight: .bold)
                                                .foregroundStyle(.primary)
                                        )
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(friend.username ?? friend.email)
                                            .appFont(.body, weight: .semibold)
                                            .foregroundStyle(primaryColor)
                                        Text(lastWorkoutText(friend: friend))
                                            .appFont(.footnote)
                                            .foregroundStyle(secondaryColor)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(secondaryColor)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { Haptics.playLightTap() })
                        }
                    }
                }
            }
        }
    }

    private func lastWorkoutText(friend: AtlasFriend) -> String {
        if let date = friend.createdAt {
            let formatted = date.formatted(.dateTime.month().day())
            return "Last workout • \(formatted)"
        }
        return "No workouts yet"
    }

    private func initials(for friend: AtlasFriend) -> String {
        let base = friend.username ?? friend.email
        let comps = base.split(separator: " ")
        if comps.count >= 2 {
            return "\(comps[0].first.map(String.init) ?? "")\(comps[1].first.map(String.init) ?? "")"
        }
        return base.prefix(2).uppercased()
    }

    private var leaderboardCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Leaderboard")
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(primaryColor)
                    Spacer()
                    Picker("Metric", selection: $leaderboardMetric) {
                        ForEach(LeaderboardMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .controlSize(.mini)
                }

                if friendsStore.friends.isEmpty {
                    Text("Add friends to see the leaderboard")
                        .appFont(.footnote)
                        .foregroundStyle(secondaryColor)
                } else {
                    VStack(spacing: 8) {
                        // Show "You" row first
                        LeaderboardRow(
                            rank: 1,
                            name: "You",
                            value: leaderboardValueForSelf(),
                            metric: leaderboardMetric,
                            isCurrentUser: true
                        )

                        // Show friends (placeholder values - actual data would come from FriendDetailModel)
                        ForEach(Array(friendsStore.friends.prefix(5).enumerated()), id: \.element.id) { index, friend in
                            LeaderboardRow(
                                rank: index + 2,
                                name: friend.username ?? friend.email.prefix(10).description,
                                value: "—",
                                metric: leaderboardMetric,
                                isCurrentUser: false
                            )
                        }
                    }
                }
            }
        }
    }

    private func leaderboardValueForSelf() -> String {
        // Placeholder - would integrate with user's stats
        switch leaderboardMetric {
        case .streak: return "—"
        case .weeklyVolume: return "—"
        case .sessions: return "—"
        }
    }

    private var unauthenticatedCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in to use Friends")
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(primaryColor)
                Text("You need an active session to view and send requests.")
                    .appFont(.body)
                    .foregroundStyle(secondaryColor)
                Button {
                    Haptics.playLightTap()
                    Task { await authStore.signOut() }
                } label: {
                    Text("Go to Sign In")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PressableGlassButtonStyle())
            }
        }
    }

    private func sendRequest() {
        Haptics.playLightTap()
        let username = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard username.isEmpty == false else { return }
        Task {
            await friendsStore.sendRequest(username: username)
            await MainActor.run {
                if friendsStore.lastErrorMessage == nil && friendsStore.uiError == nil && friendsStore.errorMessage == nil {
                    usernameInput = ""
                    dismissKeyboard()
                }
            }
        }
    }

    @MainActor
    private func refreshIfReady() async {
        if authStore.isReadyForFriends {
            await friendsStore.refreshAll()
        } else {
            setNotReadyMessage()
        }
    }

    private func setNotReadyMessage() {
        let message = "Sign in to use Friends."
        friendsStore.lastErrorMessage = message
        friendsStore.uiError = message
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let rank: Int
    let name: String
    let value: String
    let metric: FriendsView.LeaderboardMetric
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .appFont(.footnote, weight: .bold)
                .foregroundStyle(isCurrentUser ? .white : .secondary)
                .frame(width: 30, alignment: .leading)

            Text(name)
                .appFont(.body, weight: isCurrentUser ? .bold : .semibold)
                .foregroundStyle(isCurrentUser ? .white : .primary)
                .lineLimit(1)

            Spacer()

            Text(value)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(isCurrentUser ? .white : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isCurrentUser ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}
