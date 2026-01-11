import SwiftUI

enum AppTab: Hashable {
    case home
    case friends
    case stats
}

struct RootTabShellView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var usernameStore: UsernameStore
    @State private var selectedTab: AppTab = .home
    @State private var showUsernamePrompt = false
    @State private var bannerMessage: String?

    let startWorkout: () -> Void
    let openSettings: () -> Void

    private let tabHeight: CGFloat = 70
    private let tabBottomPadding: CGFloat = 10
    private let startButtonGapAboveTab: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        startWorkout: { startWorkout() },
                        openSettings: openSettings
                    )
                case .friends:
                    FriendsView()
                case .stats:
                    StatsView()
                }
            }
            .atlasBackground()
            .atlasBackgroundTheme(backgroundTheme(for: selectedTab))

            if let bannerMessage {
                Text(bannerMessage)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(14)
                    .padding(.bottom, tabHeight + tabBottomPadding + 8)
                    .transition(.opacity)
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingPillTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.bottom, tabBottomPadding)
        }
        .sheet(isPresented: $showUsernamePrompt) {
            UsernamePromptView(
                usernameStore: usernameStore,
                onSave: { normalized in
                    saveUsername(normalized)
                },
                onClose: {
                    usernameStore.dismissedPrompt = true
                    showUsernamePrompt = false
                }
            )
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .friends {
                usernameStore.dismissedPrompt = false
            }
            evaluateUsernamePrompt()
        }
        .onChange(of: authStore.isAuthenticated) { _, _ in
            evaluateUsernamePrompt()
        }
        .onChange(of: authStore.isProfileLoaded) { _, _ in
            evaluateUsernamePrompt()
        }
        .onChange(of: authStore.username) { _, newValue in
            if let newValue, newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                usernameStore.username = newValue
            }
            evaluateUsernamePrompt()
        }
        .onAppear {
            evaluateUsernamePrompt()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func evaluateUsernamePrompt() {
        let remoteEnabled = authStore.isReadyForFriends
        let remoteMissing = authStore.username?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let shouldShow = authStore.isAuthenticated && authStore.isProfileLoaded && remoteEnabled && selectedTab == .friends && usernameStore.dismissedPrompt == false && usernameStore.hasUsername == false && remoteMissing
        #if DEBUG
        if shouldShow {
            print("[USERNAME][PROMPT] showing prompt auth=\(authStore.isAuthenticated) profileLoaded=\(authStore.isProfileLoaded) remoteEnabled=\(remoteEnabled) remoteMissing=\(remoteMissing) dismissed=\(usernameStore.dismissedPrompt)")
        } else {
            print("[USERNAME][PROMPT] hidden auth=\(authStore.isAuthenticated) profileLoaded=\(authStore.isProfileLoaded) remoteEnabled=\(remoteEnabled) remoteMissing=\(remoteMissing) dismissed=\(usernameStore.dismissedPrompt) hasLocal=\(usernameStore.hasUsername) selectedTab=\(selectedTab)")
        }
        #endif
        showUsernamePrompt = shouldShow
    }

    private func saveUsername(_ normalized: String) {
        usernameStore.username = normalized
        usernameStore.dismissedPrompt = true
        showUsernamePrompt = false
        Task {
            let errorMessage = await authStore.setUsername(normalized)
            if let errorMessage {
                #if DEBUG
                print("[USERNAME][REMOTE][WARN] remote save failed: \(errorMessage)")
                #endif
                await MainActor.run {
                    bannerMessage = "Saved locally — will sync later."
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeInOut) {
                        bannerMessage = nil
                    }
                }
            } else {
                #if DEBUG
                print("[USERNAME][REMOTE] remote save success")
                #endif
            }
        }
    }
}


    private func backgroundTheme(for tab: AppTab) -> BackgroundTheme {
        switch tab {
        case .home: return .home
        case .friends: return .friends
        case .stats: return .stats
        }
    }
