import SwiftUI

struct UsernamePromptView: View {
    @ObservedObject var usernameStore: UsernameStore
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var input: String = ""
    @State private var statusText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    HStack {
                        Text("Create a username")
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            Haptics.playLightTap()
                            usernameStore.dismissedPrompt = true
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .appFont(.section, weight: .semibold)
                                .foregroundStyle(.secondary)
                            TextField("username", text: $input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.default)
                                .submitLabel(.done)
                                .onSubmit { submit() }
                                .padding(AppStyle.settingsGroupPadding)
                                .atlasGlassCard()
                        }
                        Text("3–20 chars · a–z, 0–9, underscore")
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Haptics.playLightTap()
                        submit()
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .atlasGlassCard()
                    }
                    .disabled(isValid == false)

                    if let statusText {
                        Text(statusText)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .tint(.primary)
            .atlasBackground()
            .atlasBackgroundTheme(.auth)
        }
        .onAppear {
            if usernameStore.hasUsername {
                input = usernameStore.username
            }
        }
    }

    private var isValid: Bool {
        let normalized = normalizedInput()
        guard normalized.count >= 3 && normalized.count <= 20 else { return false }
        return normalized.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil
    }

    private func normalizedInput() -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func submit() {
        guard isValid else {
            statusText = "Usernames are 3–20 chars: a–z, 0–9, underscore."
            return
        }
        statusText = nil
        let normalized = normalizedInput()
        usernameStore.username = normalized
        onSave(normalized)
    }
}
