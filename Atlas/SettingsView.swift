//
//  SettingsView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct SettingsView: View {
    @Binding var isDarkMode: Bool
    let onDismiss: () -> Void
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @State private var showWeightPicker = false

    /// Builds the full-screen settings page with monochrome appearance controls.
    /// Change impact: Adjusting layout, card fills, or typography changes the calm, premium feel of the settings experience.
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsHeaderBar(title: "Settings", onDismiss: onDismiss)
                        .padding(.top, 6)

                    // Appearance selector via single pill + dropdown.
                    SettingsSectionLabel(text: "APPEARANCE")
                    SettingsGroupCard {
                        Menu {
                            Button("Light Mode") {
                                withAnimation(AppMotion.primary) {
                                    isDarkMode = false
                                }
                            }
                            Button("Dark Mode") {
                                withAnimation(AppMotion.primary) {
                                    isDarkMode = true
                                }
                            }
                        } label: {
                            SettingsRowLabel(
                                title: "Theme",
                                value: isDarkMode ? "Dark Mode" : "Light Mode",
                                showsChevron: true
                            )
                            .contentShape(Rectangle())
                        }
                    }

                    // Weight units.
                    SettingsSectionLabel(text: "WEIGHT UNITS")
                    SettingsGroupCard {
                        SettingsRow(
                            title: "Weight Units",
                            value: weightUnitDisplay,
                            showsChevron: true,
                            action: { showWeightPicker = true }
                        )
                    }

                    // Data source.
                    SettingsSectionLabel(text: "DATA SOURCE")
                    SettingsGroupCard {
                        Text("Currently using: Apple Health")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                        divider
                        SettingsRow(
                            title: "Data Source",
                            value: "Apple Health",
                            showsChevron: true,
                            action: {}
                        )
                    }

                    // Apple Health integration.
                    SettingsSectionLabel(text: "APPLE HEALTH INTEGRATION")
                    SettingsGroupCard {
                        SettingsRow(
                            title: "Apple Health Connected",
                            value: nil,
                            showsChevron: false,
                            action: {}
                        )
                    }

                    // Instagram.
                    SettingsSectionLabel(text: "INSTAGRAM")
                    SettingsGroupCard {
                        SettingsRow(
                            title: "Tag and explore @bhagyeshsagole",
                            value: nil,
                            showsChevron: false,
                            action: {}
                        )
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 40)
            }
        }
        .tint(.primary)
        .confirmationDialog("Select Weight Units", isPresented: $showWeightPicker, titleVisibility: .visible) {
            Button("Pounds (lb)") {
                withAnimation(AppMotion.primary) {
                    weightUnit = "lb"
                }
            }
            Button("Kilograms (kg)") {
                withAnimation(AppMotion.primary) {
                    weightUnit = "kg"
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    /// Computes the display label for the stored weight unit.
    /// Change impact: Editing this mapping changes how the unit text appears in the UI.
    private var weightUnitDisplay: String {
        weightUnit == "kg" ? "Kilograms (kg)" : "Pounds (lb)"
    }

    /// Builds the background color tuned for the current theme.
    /// Change impact: Adjusting opacities here shifts overall contrast for light/dark mode.
    private var backgroundColor: Color {
        isDarkMode ? Color.black.opacity(0.94) : Color.white.opacity(0.96)
    }

    /// Provides a thin monochrome divider used between stacked rows.
    /// Change impact: Altering opacity changes how strong the separation feels between items.
    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(isDarkMode ? 0.18 : 0.22))
            .frame(height: 1)
    }
}

struct SettingsHeaderBar: View {
    let title: String
    let onDismiss: () -> Void

    /// Builds the top bar with dismiss X and centered title.
    /// Change impact: Adjusting padding or icon styling alters perceived density and hierarchy of the header.
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.custom("Helvetica Neue", size: 16).weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            Spacer()
            Text(title)
                .font(.custom("Helvetica Neue", size: 20).weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Color.clear.frame(width: 40)
        }
    }
}

struct SettingsSectionLabel: View {
    let text: String

    /// Renders a compact uppercase section label in secondary tone.
    /// Change impact: Adjusting font or opacity shifts perceived grouping strength.
    var body: some View {
        Text(text)
            .font(.custom("Helvetica Neue", size: 12).weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }
}

struct SettingsGroupCard<Content: View>: View {
    @ViewBuilder let content: Content
    private let cornerRadius: CGFloat = 18

    /// Wraps rows in a glass-like card with subtle stroke and shadow.
    /// Change impact: Tweaking corner radius or fill opacity changes the sense of depth across all settings groups.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}

struct SettingsRow: View {
    let title: String
    let value: String?
    let showsChevron: Bool
    let action: () -> Void

    /// Builds a monochrome settings row with optional value and chevron.
    /// Change impact: Adjusting spacing or chevron visibility changes tap targets and hierarchy.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .font(.custom("Helvetica Neue", size: 15))
                        .foregroundStyle(.secondary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.custom("Helvetica Neue", size: 13).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let value: String?
    let showsChevron: Bool

    /// Presents a non-interactive row layout for use as labels (e.g., Menu labels).
    /// Change impact: Adjusting fonts or spacing shifts how the label aligns with tappable rows.
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundStyle(.primary)
            Spacer()
            if let value {
                Text(value)
                    .font(.custom("Helvetica Neue", size: 15))
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.custom("Helvetica Neue", size: 13).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView(isDarkMode: .constant(true), onDismiss: {})
}
