import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        Group {
            if authStore.isAuthenticated == false {
                AuthLandingView()
            } else if authStore.isProfileLoaded == false {
                ProfileLoadingView()
            } else {
                ContentView()
            }
        }
        .task {
            authStore.startIfNeeded()
        }
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
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Atlas")
                        .appFont(.brand)
                        .foregroundStyle(.primary)
                    Text("Sign in to continue")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                        .opacity(0.8)
                }

                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .appFont(.section, weight: .semibold)
                            .foregroundStyle(.secondary)
                        TextField("you@example.com", text: $emailInput)
                            .textInputAutocapitalization(.never)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .submitLabel(.next)
                            .autocorrectionDisabled(true)
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .appFont(.section, weight: .semibold)
                            .foregroundStyle(.secondary)
                        SecureField("••••••••", text: $passwordInput)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { Task { await signIn() } }
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                    }
                }

                Button {
                    Haptics.playLightTap()
                    Task { await signIn() }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView()
                                .tint(.primary)
                        }
                        Text("Sign In")
                    }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                }
                .disabled(isWorking || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || passwordInput.isEmpty)

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
                .disabled(isWorking || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || passwordInput.isEmpty)

                if let status {
                    Text(status.message)
                        .appFont(.body)
                        .foregroundStyle(status.style)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
            .padding(.bottom, AppStyle.settingsBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .tint(.primary)
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

        let errorMessage = await authStore.signUp(email: emailInput, password: passwordInput, username: nil)
        if let errorMessage {
            status = .error(errorMessage)
        } else {
            status = .success("Check your email and verify account, then sign in.")
        }
    }

}
