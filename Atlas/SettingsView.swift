//
//  SettingsView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct SettingsView: View {
    @Binding var isDarkMode: Bool
    @Environment(\.dismiss) private var dismiss

    /// Builds the full-screen settings page with monochrome appearance controls.
    /// Change impact: Adjusting spacing, corner radii, or fills changes the feel of the settings sheet navigation.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header row with back chevron and title.
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                Spacer()
                Text("Settings")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 40)
            }

            // Appearance section header.
            Text("APPEARANCE")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 14) {
                settingRow(
                    title: "Light Mode",
                    detail: "Brighter glass surfaces",
                    isSelected: !isDarkMode
                ) {
                    withAnimation(AppMotion.primary) {
                        isDarkMode = false
                    }
                }

                settingRow(
                    title: "Dark Mode",
                    detail: "Dimmer, deeper glass",
                    isSelected: isDarkMode
                ) {
                    withAnimation(AppMotion.primary) {
                        isDarkMode = true
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .background(
            Color.black.opacity(0.94)
                .ignoresSafeArea()
        )
    }

    /// Builds a monochrome settings row with a pill background and selection state.
    /// Change impact: Tweaking corner radius or opacity adjusts the density of each row.
    private func settingRow(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(isSelected ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(isSelected ? 0.28 : 0.16), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SettingsView(isDarkMode: .constant(true))
}
