import SwiftUI

struct AuthDebugView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var emailInput: String = ""
    @State private var statusMessage: String?
    @State private var isSending = false

    private var isAuthenticated: Bool { authStore.isAuthenticated }
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(AppStyle.settingsBackgroundOpacityDark) : Color.white.opacity(AppStyle.settingsBackgroundOpacityLight)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: AppStyle.sectionSpacing) {
                header

                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    Text("Email")
                        .appFont(.section, weight: .semibold)
                        .foregroundStyle(.secondary)
                    TextField("you@example.com", text: $emailInput)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)
                        .padding(AppStyle.settingsGroupPadding)
                        .atlasGlassCard()
                }

                Button {
                    Task { await sendMagicLink() }
                } label: {
                    Text(isSending ? "Sending..." : "Send magic link")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                }
                .disabled(isSending || emailInput.isEmpty)

                if let statusMessage {
                    Text(statusMessage)
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                }

                if isAuthenticated {
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        Text("Signed in")
                            .appFont(.section, weight: .semibold)
                        if let email = authStore.email {
                            Text(email).appFont(.body)
                        }
                        if let userId = authStore.userId {
                            Text(userId).appFont(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await authStore.signOut() }
                        } label: {
                            Text("Sign out")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .atlasGlassCard()
                        }
                    }
                }

                Spacer()
            }
            .padding(AppStyle.screenHorizontalPadding)
            .padding(.top, AppStyle.screenTopPadding)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .appFont(.body, weight: .semibold)
                    .padding(10)
                    .atlasGlassCard()
            }
            Spacer()
            Text("Account (Beta)")
                .appFont(.title, weight: .semibold)
            Spacer()
            Color.clear.frame(width: 44)
        }
    }

    private func sendMagicLink() async {
        guard isSending == false else { return }
        isSending = true
        statusMessage = nil
        defer { isSending = false }

        let trimmed = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter an email to send the link."
            return
        }

        do {
            try await authStore.sendMagicLink(email: trimmed, redirectURL: URL(string: "atlas://auth-callback"))
            statusMessage = "Magic link sent. Check your email."
        } catch {
            statusMessage = "Failed to send link: \(error.localizedDescription)"
        }
    }
}
