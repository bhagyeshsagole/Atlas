import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var friendsStore: FriendsStore
    @EnvironmentObject private var usernameStore: UsernameStore
    @State private var usernameInput: String = ""
    @State private var leaderboardMetric: LeaderboardMetric = .streak
    @State private var isSendingRequest: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showCopiedToast: Bool = false
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

            // Toast overlay
            if showCopiedToast {
                VStack {
                    Spacer()
                    ToastView(message: "Username copied")
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: showCopiedToast)
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Share Text

    private var shareText: String {
        let username = usernameStore.username.isEmpty ? "" : "@\(usernameStore.username)"
        return "Join me on Atlas - track your workouts and compete with friends! \(username)\n\n\(AppLinks.atlasInviteURL)"
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Friends")
                .appFont(.title, weight: .semibold)
                .foregroundStyle(primaryColor)
            Spacer()
            if friendsStore.isLoading {
                ProgressView()
                    .tint(primaryColor)
            } else {
                // Share button
                AtlasHeaderIconButton(systemName: "square.and.arrow.up", isGlassBackplate: true) {
                    Haptics.playLightTap()
                    showShareSheet = true
                }

                // Refresh button
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

    // MARK: - Add Friend Card (Batch 1 fix)

    private var addFriendCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                // Header with optional copy username button
                HStack {
                    Text("Add friend")
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(primaryColor)
                    Spacer()
                    if usernameStore.hasUsername {
                        Button {
                            copyUsername()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("@\(usernameStore.username)")
                                    .appFont(.caption, weight: .semibold)
                            }
                            .foregroundStyle(secondaryColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Composer row: input + send button aligned
                HStack(spacing: 10) {
                    // Input field
                    TextField("Username or email", text: $usernameInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .foregroundStyle(primaryColor)
                        .tint(primaryColor)
                        .appFont(.body, weight: .regular)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                        .submitLabel(.send)
                        .onSubmit {
                            if isValidInput && !friendsStore.isLoading {
                                sendRequest()
                            }
                        }
                        .accessibilityLabel("Friend username or email")

                    // Send button - matching glass style
                    Button {
                        sendRequest()
                    } label: {
                        HStack(spacing: 6) {
                            if isSendingRequest {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(primaryColor)
                            } else {
                                Text("Send")
                                    .appFont(.body, weight: .semibold)
                            }
                        }
                        .foregroundStyle(isValidInput ? primaryColor : secondaryColor)
                        .frame(width: 80, height: 44)
                        .background(Color.white.opacity(isValidInput ? 0.12 : 0.06))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValidInput || friendsStore.isLoading || isSendingRequest)
                    .accessibilityLabel("Send friend request")
                }
            }
        }
    }

    private var isValidInput: Bool {
        !usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Requests Card (Batch 4: better empty state)

    private var requestsCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Requests")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(primaryColor)
                if friendsStore.incomingRequests.isEmpty && friendsStore.outgoingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.badge")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("No requests")
                                .appFont(.footnote)
                                .foregroundStyle(secondaryColor)
                        }
                        // Actionable empty state
                        Text("Share your username to get added faster")
                            .appFont(.caption)
                            .foregroundStyle(secondaryColor.opacity(0.7))
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

    // MARK: - Friends Card (Batch 3: micro-interactions)

    private var friendsCard: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(primaryColor)
                if friendsStore.friends.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No friends yet")
                            .appFont(.footnote)
                            .foregroundStyle(secondaryColor)
                        Text("Invite friends to start competing")
                            .appFont(.caption)
                            .foregroundStyle(secondaryColor.opacity(0.7))
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(friendsStore.friends) { friend in
                            FriendRow(
                                friend: friend,
                                initials: initials(for: friend),
                                statusText: friendStatusText(friend: friend),
                                isActive: isRecentlyActive(friend: friend)
                            )
                        }
                    }
                }
            }
        }
    }

    private func friendStatusText(friend: AtlasFriend) -> String {
        if isRecentlyActive(friend: friend) {
            return "Active"
        }
        if let date = friend.createdAt {
            let formatted = date.formatted(.dateTime.month().day())
            return "Last workout \(formatted)"
        }
        return "No workouts yet"
    }

    private func isRecentlyActive(friend: AtlasFriend) -> Bool {
        guard let date = friend.createdAt else { return false }
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        return date >= twoDaysAgo
    }

    private func initials(for friend: AtlasFriend) -> String {
        let base = friend.username ?? friend.email
        let comps = base.split(separator: " ")
        if comps.count >= 2 {
            return "\(comps[0].first.map(String.init) ?? "")\(comps[1].first.map(String.init) ?? "")"
        }
        return base.prefix(2).uppercased()
    }

    // MARK: - Leaderboard Card (Batch 4: better empty state)

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add friends to compete")
                            .appFont(.footnote)
                            .foregroundStyle(secondaryColor)
                        Text("See who's crushing their workouts")
                            .appFont(.caption)
                            .foregroundStyle(secondaryColor.opacity(0.7))
                    }
                } else {
                    VStack(spacing: 8) {
                        LeaderboardRow(
                            rank: 1,
                            name: "You",
                            value: leaderboardValueForSelf(),
                            metric: leaderboardMetric,
                            isCurrentUser: true
                        )

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

    // MARK: - Actions

    private func sendRequest() {
        let username = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard username.isEmpty == false else { return }

        Haptics.playLightTap()
        isSendingRequest = true

        Task {
            await friendsStore.sendRequest(username: username)
            await MainActor.run {
                isSendingRequest = false
                if friendsStore.lastErrorMessage == nil && friendsStore.uiError == nil && friendsStore.errorMessage == nil {
                    Haptics.playMediumTap()
                    usernameInput = ""
                    dismissKeyboard()
                } else {
                    Haptics.playHeavyImpact()
                }
            }
        }
    }

    private func copyUsername() {
        guard usernameStore.hasUsername else { return }
        UIPasteboard.general.string = usernameStore.username
        Haptics.playLightTap()

        withAnimation {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
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

// MARK: - Friend Row (Batch 3: micro-interactions)

private struct FriendRow: View {
    let friend: AtlasFriend
    let initials: String
    let statusText: String
    let isActive: Bool

    @State private var showNudgeSheet: Bool = false

    private let primaryColor = Color.white
    private let secondaryColor = Color.white.opacity(0.72)

    var body: some View {
        NavigationLink(destination: FriendDetailView(friend: friend)) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(initials)
                            .appFont(.body, weight: .bold)
                            .foregroundStyle(.primary)
                    )

                // Name and status
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(friend.username ?? friend.email)
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(primaryColor)

                        // Active indicator
                        if isActive {
                            Text("Active")
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    Text(statusText)
                        .appFont(.footnote)
                        .foregroundStyle(secondaryColor)
                }

                Spacer()

                // Nudge button (swipe alternative - always visible as icon)
                Button {
                    Haptics.playLightTap()
                    showNudgeSheet = true
                } label: {
                    Image(systemName: "hand.wave")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryColor)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondaryColor)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.playLightTap() })
        .sheet(isPresented: $showNudgeSheet) {
            ShareSheet(items: [nudgeMessage])
        }
    }

    private var nudgeMessage: String {
        let name = friend.username ?? friend.email.prefix(10).description
        return "Hey \(name)! Get your workout in today. Let's keep the streak going!"
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

// MARK: - Toast View

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .appFont(.footnote, weight: .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - App Links

enum AppLinks {
    static let atlasInviteURL = "https://apps.apple.com/app/atlas-workout"
}
