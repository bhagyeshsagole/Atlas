import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.isAuthenticated == false {
                AuthLandingView()
            } else if authStore.isProfileLoaded == false {
                ProfileLoadingView()
            } else if authStore.needsOnboarding {
                TrainingProfileOnboardingView { }
            } else {
                ContentView()
            }
        }
        .task {
            authStore.startIfNeeded()
        }
        .atlasBackgroundTheme(.auth)
    }
}

private struct ProfileLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.primary)
                Text("Loading profile…")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AuthLandingView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var usernameInput: String = ""
    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var status: Status?
    @State private var isWorking = false

    private enum Status {
        case info(String)
        case success(String)
        case error(String)

        var message: String {
            switch self {
            case .info(let text), .success(let text), .error(let text):
                return text
            }
        }

        var style: Color {
            switch self {
            case .info:
                return .secondary
            case .success:
                return .green.opacity(0.9)
            case .error:
                return .red
            }
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome")
                            .appFont(.brand)
                            .foregroundStyle(.primary)
                    Text("Sign in to continue")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                            .opacity(0.9)
                    }

                    VStack(spacing: 12) {
                        GlassInputRow(title: "Username", placeholder: "atlas_user", text: $usernameInput, icon: "person.fill", isSecure: false, keyboard: .asciiCapable)
                        GlassInputRow(title: "Email", placeholder: "you@example.com", text: $emailInput, icon: "envelope.fill", isSecure: false, keyboard: .emailAddress)
                        GlassInputRow(title: "Password", placeholder: "••••••••", text: $passwordInput, icon: "lock.fill", isSecure: true, keyboard: .default, onSubmit: { Task { await signIn() } })
                    }

                    VStack(spacing: 12) {
                        Button {
                            Haptics.playLightTap()
                            Task { await signIn() }
                        } label: {
                            HStack {
                                if isWorking { ProgressView().tint(.primary) }
                                Text("Continue")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .atlasGlassCard()
                        }
                        .disabled(isWorking || !isFormValid)

                        Button {
                            Haptics.playLightTap()
                            Task { await signUp() }
                        } label: {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .atlasGlassCard()
                                .opacity(0.9)
                        }
                        .disabled(isWorking || !isFormValid)

                        Button {
                            Haptics.playLightTap()
                            authStore.activateDemoMode()
                        } label: {
                            Text("Continue in Demo Mode")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .atlasGlassCard()
                                .opacity(0.85)
                        }
                        .disabled(isWorking)
                    }

                    if let status {
                        Text(status.message)
                            .appFont(.body)
                            .foregroundStyle(status.style)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(.primary)
        .atlasBackground()
    }

    private var isFormValid: Bool {
        usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        passwordInput.isEmpty == false
    }

    @MainActor
    private func signIn() async {
        guard isWorking == false else { return }
        isWorking = true
        status = nil
        defer { isWorking = false }

        #if DEBUG
        print("[AUTH][UI] signIn begin email=\(emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
        #endif
        let errorMessage = await authStore.signIn(email: emailInput, password: passwordInput)
        if let errorMessage {
            status = .error(errorMessage)
            #if DEBUG
            print("[AUTH][UI] signIn failed: \(errorMessage)")
            #endif
        } else {
            #if DEBUG
            print("[AUTH][UI] signIn ok user=\(authStore.userId ?? "nil")")
            #endif
        }
    }

    @MainActor
    private func signUp() async {
        guard isWorking == false else { return }
        isWorking = true
        status = nil
        defer { isWorking = false }

        let errorMessage = await authStore.signUp(email: emailInput, password: passwordInput, username: usernameInput)
        if let errorMessage {
            status = .error(errorMessage)
        } else {
            status = .success("Check your email and verify account, then sign in.")
        }
    }

}

private struct GlassInputRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.section, weight: .semibold)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { onSubmit?() }
                    } else {
                        TextField(placeholder, text: $text)
                            .textContentType(keyboard == .emailAddress ? .emailAddress : .username)
                            .submitLabel(.next)
                    }
                }
                .textInputAutocapitalization(.never)
                .keyboardType(keyboard)
                .autocorrectionDisabled(true)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(AppStyle.settingsGroupPadding)
            .atlasGlassCard()
        }
    }
}
