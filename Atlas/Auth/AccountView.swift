import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var emailIsFocused: Bool
    @State private var emailInput: String = ""
    @State private var status: Status?
    @State private var isSending = false

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
            case .info, .success:
                return .secondary
            case .error:
                return .red
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(AppStyle.settingsBackgroundOpacityDark) : Color.white.opacity(AppStyle.settingsBackgroundOpacityLight)
    }

    private var redirectURL: URL {
        if
            let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_REDIRECT_URL") as? String,
            value.isEmpty == false,
            let url = URL(string: value)
        {
            return url
        }
        return URL(string: "atlas://auth-callback")!
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    header

                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        Text("Email")
                            .appFont(.section, weight: .semibold)
                            .foregroundStyle(.secondary)
                        TextField("you@example.com", text: $emailInput)
                            .textInputAutocapitalization(.never)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .focused($emailIsFocused)
                            .submitLabel(.send)
                            .onSubmit { Task { await sendMagicLink() } }
                            .autocorrectionDisabled(true)
                            .padding(AppStyle.settingsGroupPadding)
                            .atlasGlassCard()
                    }

                    Button {
                        Haptics.playLightTap()
                        Task { await sendMagicLink() }
                    } label: {
                        Text(isSending ? "Sending..." : "Send Magic Link")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .atlasGlassCard()
                    }
                    .disabled(isSending || emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let status {
                        Text(status.message)
                            .appFont(.body)
                            .foregroundStyle(status.style)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if authStore.isAuthenticated {
                        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                            Text("Signed in as")
                                .appFont(.section, weight: .semibold)
                            if let email = authStore.email {
                                Text(email).appFont(.body)
                            }
                            if let userId = authStore.userId {
                                Text(userId)
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                Haptics.playLightTap()
                                Task { await signOut() }
                            } label: {
                                Text("Sign out")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .atlasGlassCard()
                            }
                        }
                    }

                    Spacer(minLength: AppStyle.sectionSpacing)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: AppStyle.sectionSpacing)
            }
        }
        .tint(.primary)
        .onAppear {
            if emailInput.isEmpty, let email = authStore.email {
                emailInput = email
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                Haptics.playLightTap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .appFont(.body, weight: .semibold)
                    .padding(10)
                    .atlasGlassCard()
            }
            Spacer()
            Text("Account (Beta)")
                .appFont(.title, weight: .semibold)
            Spacer()
            Color.clear.frame(width: AtlasControlTokens.headerButtonSize)
        }
    }

    @MainActor
    private func sendMagicLink() async {
        guard isSending == false else { return }
        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            status = .info("Enter an email to send the link.")
            return
        }

        isSending = true
        status = nil
        defer { isSending = false }

        do {
            try await authStore.sendMagicLink(email: trimmed, redirectURL: redirectURL)
            status = .success("Magic link sent. Check your email.")
        } catch {
            status = .error("Failed to send link: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func signOut() async {
        status = nil
        await authStore.signOut()
        status = .info("Signed out.")
    }
}

#Preview("Account – iPhone SE (3rd gen)") {
    AccountView()
        .environmentObject(AuthStore())
        .previewDevice("iPhone SE (3rd generation)")
}

#Preview("Account – iPhone 15 Pro") {
    AccountView()
        .environmentObject(AuthStore())
        .previewDevice("iPhone 15 Pro")
}

#Preview("Account – iPhone 15 Pro Max") {
    AccountView()
        .environmentObject(AuthStore())
        .previewDevice("iPhone 15 Pro Max")
}
