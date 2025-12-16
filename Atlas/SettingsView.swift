//
//  SettingsView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct SettingsView: View {
    let onDismiss: () -> Void
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var activeDropdown: DropdownType?

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

                    // Appearance selector via shared dropdown menu.
                    SettingsSectionLabel(text: "APPEARANCE")
                    SettingsGroupCard {
                        SettingsDropdownRow(
                            title: "Appearance",
                            value: appearanceLabel,
                            isOpen: activeDropdown == .appearance,
                            options: [
                                MenuOption(id: "light", title: "Light"),
                                MenuOption(id: "dark", title: "Dark")
                            ],
                            onTap: {
                                withAnimation(AppMotion.primary) {
                                    activeDropdown = activeDropdown == .appearance ? nil : .appearance
                                }
                            },
                            onSelect: { id in
                                withAnimation(AppMotion.primary) {
                                    appearanceMode = id
                                    activeDropdown = nil
                                }
                                dismiss()
                                onDismiss()
                            }
                        )
                    }

                    // Weight units selector via shared picker sheet.
                    SettingsSectionLabel(text: "WEIGHT UNITS")
                    SettingsGroupCard {
                        SettingsDropdownRow(
                            title: "Weight Units",
                            value: weightUnitDisplay,
                            isOpen: activeDropdown == .weight,
                            options: [
                                MenuOption(id: "lb", title: "Pounds (lb)"),
                                MenuOption(id: "kg", title: "Kilograms (kg)")
                            ],
                            onTap: {
                                withAnimation(AppMotion.primary) {
                                    activeDropdown = activeDropdown == .weight ? nil : .weight
                                }
                            },
                            onSelect: { id in
                                withAnimation(AppMotion.primary) {
                                    weightUnit = id
                                    activeDropdown = nil
                                }
                            }
                        )
                    }

                    // Instagram row.
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
        .contentShape(Rectangle())
        .onTapGesture {
            if activeDropdown != nil {
                withAnimation(AppMotion.primary) {
                    activeDropdown = nil
                }
            }
        }
    }

    /// Computes the display label for the stored appearance.
    /// Change impact: Editing this mapping changes how the appearance row reads.
    private var appearanceLabel: String {
        appearanceMode == "dark" ? "Dark" : "Light"
    }

    /// Computes the display label for the stored weight unit.
    /// Change impact: Editing this mapping changes how the unit text appears in the UI.
    private var weightUnitDisplay: String {
        weightUnit == "kg" ? "Kilograms (kg)" : "Pounds (lb)"
    }

    /// Builds the background color tuned for the current theme.
    /// Change impact: Adjusting opacities here shifts overall contrast for light/dark mode.
    private var backgroundColor: Color {
        appearanceMode == "dark" ? Color.black.opacity(0.94) : Color.white.opacity(0.96)
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

struct SettingsDropdownRow: View {
    let title: String
    let value: String
    let isOpen: Bool
    let options: [MenuOption]
    let onTap: () -> Void
    let onSelect: (String) -> Void

    /// Provides a stable row that triggers a trailing dropdown without hiding label/value.
    /// Change impact: Adjusting fonts or padding changes the touch target feel for all dropdowns.
    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(value)
                        .font(.custom("Helvetica Neue", size: 15))
                        .foregroundStyle(.secondary.opacity(isOpen ? 0.8 : 1.0))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.custom("Helvetica Neue", size: 13).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                DropdownMenuView(options: options, onSelect: onSelect)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .animation(AppMotion.primary, value: isOpen)
            }
        }
    }
}

struct DropdownMenuView: View {
    let options: [MenuOption]
    let onSelect: (String) -> Void

    /// Renders the compact trailing dropdown menu with glass styling.
    /// Change impact: Adjusting corner radius or opacity changes perceived depth for all dropdowns.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    Text(option.title)
                        .font(.custom("Helvetica Neue", size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MenuOption: Identifiable {
    let id: String
    let title: String
}

enum DropdownType {
    case appearance
    case weight
}

#Preview {
    SettingsView(onDismiss: {})
}
