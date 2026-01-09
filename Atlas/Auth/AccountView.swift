import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var status: String?

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(AppStyle.settingsBackgroundOpacityDark) : Color.white.opacity(AppStyle.settingsBackgroundOpacityLight)
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    header

                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        Text("Signed in as")
                            .appFont(.section, weight: .semibold)
                        Text(authStore.email ?? "—")
                            .appFont(.body)
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
                        .disabled(authStore.isAuthenticated == false)
                    }

                    if let status {
                        Text(status)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
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
    private func signOut() async {
        status = nil
        await authStore.signOut()
        status = "Signed out."
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
