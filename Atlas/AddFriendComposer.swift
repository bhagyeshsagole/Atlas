//
//  AddFriendComposer.swift
//  Atlas
//
//  What this file is:
//  - Unified "Add friend" input + send button composer with consistent glass styling.
//
//  Where it's used:
//  - Embedded in FriendsView for adding friends by username/email.
//
//  Key concepts:
//  - Input and button share same height, corner radius, and glass treatment.
//  - Supports disabled/loading states with inline spinner.
//  - Keyboard return triggers send.
//

import SwiftUI

struct AddFriendComposer: View {
    @Binding var usernameInput: String
    let isLoading: Bool
    let isSending: Bool
    let onSend: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let composerHeight: CGFloat = 44
    private let cornerRadius: CGFloat = 14
    private let primaryColor = Color.white
    private let secondaryColor = Color.white.opacity(0.72)

    private var isValidInput: Bool {
        !usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add friend")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(primaryColor)

            HStack(spacing: 10) {
                // Input field
                TextField("Username or email", text: $usernameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .foregroundStyle(primaryColor)
                    .tint(primaryColor)
                    .appFont(.body, weight: .regular)
                    .padding(.horizontal, 14)
                    .frame(height: composerHeight)
                    .background(inputBackground)
                    .overlay(inputBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        if isValidInput && !isLoading {
                            onSend()
                        }
                    }
                    .accessibilityLabel("Friend username or email")

                // Send button
                Button {
                    onSend()
                } label: {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(primaryColor)
                        } else {
                            Text("Send")
                                .appFont(.body, weight: .semibold)
                        }
                    }
                    .foregroundStyle(isValidInput ? primaryColor : secondaryColor)
                    .frame(width: 80, height: composerHeight)
                    .background(buttonBackground)
                    .overlay(buttonBorder)
                }
                .buttonStyle(.plain)
                .disabled(!isValidInput || isLoading || isSending)
                .accessibilityLabel("Send friend request")
                .accessibilityHint(isValidInput ? "Sends request to \(usernameInput)" : "Enter a username first")
            }
        }
    }

    // MARK: - Glass Styling

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.06))
    }

    private var inputBorder: some View {
        let strokeOpacity = colorScheme == .dark ? 0.12 : 0.10
        return RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
    }

    private var buttonBackground: some View {
        let fillOpacity = isValidInput ? 0.12 : 0.06
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(fillOpacity))
    }

    private var buttonBorder: some View {
        let strokeOpacity = colorScheme == .dark ? 0.18 : 0.14
        return RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
    }
}
