//
//  SettingsView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct SettingsView: View {
    let onDismiss: () -> Void
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @State private var activePicker: PickerType?
    @Environment(\.colorScheme) private var colorScheme

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

                    // Appearance selector via shared picker sheet.
                    SettingsSectionLabel(text: "APPEARANCE")
                    SettingsGroupCard {
                        SettingsPickerRow(
                            title: "Appearance",
                            value: appearanceLabel,
                            onTap: { activePicker = .appearance }
                        )
                    }

                    // Weight units selector via shared picker sheet.
                    SettingsSectionLabel(text: "WEIGHT UNITS")
                    SettingsGroupCard {
                        SettingsPickerRow(
                            title: "Weight Units",
                            value: weightUnitDisplay,
                            onTap: { activePicker = .weight }
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
        .sheet(item: $activePicker) { picker in
            PickerSheet(
                title: picker.title,
                options: picker.options,
                selectedID: pickerSelectionID(picker),
                onSelect: { id in
                    applySelection(for: picker, id: id)
                    activePicker = nil
                },
                onDismiss: { activePicker = nil }
            )
            .presentationDetents([.fraction(0.32)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Computes the display label for the stored appearance.
    /// Change impact: Editing this mapping changes how the appearance row reads.
    private var appearanceLabel: String {
        switch appearanceMode {
        case "light": return "Light"
        case "dark": return "Dark"
        default: return "System"
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
        switch appearanceMode {
        case "dark":
            return Color.black.opacity(0.94)
        case "light":
            return Color.white.opacity(0.96)
        default:
            return colorScheme == .dark ? Color.black.opacity(0.94) : Color.white.opacity(0.96)
        }
    }

    /// Returns the currently selected option id for the active picker.
    /// Change impact: Altering mapping changes which option shows as checked.
    private func pickerSelectionID(_ picker: PickerType) -> String {
        switch picker {
        case .appearance:
            return appearanceMode
        case .weight:
            return weightUnit
        }
    }

    /// Applies the chosen option to the appropriate setting.
    /// Change impact: Updating stored value changes app appearance or unit globally.
    private func applySelection(for picker: PickerType, id: String) {
        withAnimation(AppMotion.primary) {
            switch picker {
            case .appearance:
                appearanceMode = id
            case .weight:
                weightUnit = id
            }
        }
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

struct SettingsPickerRow: View {
    let title: String
    let value: String
    let onTap: () -> Void

    /// Provides a stable row that triggers a picker sheet without hiding label/value.
    /// Change impact: Altering fonts or padding changes the touch target feel for all dropdowns.
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.custom("Helvetica Neue", size: 15))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.custom("Helvetica Neue", size: 13).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PickerSheet: View {
    let title: String
    let options: [PickerOption]
    let selectedID: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Builds a monochrome bottom sheet with selectable options and checkmarks.
    /// Change impact: Adjusting corner radius or fills alters perceived depth and calmness of the picker.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 18).weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.custom("Helvetica Neue", size: 14).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }

            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundStyle(.primary)
                            Spacer()
                            if option.id == selectedID {
                                Image(systemName: "checkmark")
                                    .font(.custom("Helvetica Neue", size: 14).weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(sheetBackground)
        )
        .presentationBackground(.clear)
        .tint(.primary)
    }

    /// Resolves the sheet background to align with appearance.
    /// Change impact: Adjusting this shifts contrast and perceived depth of the picker sheet.
    private var sheetBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.black.opacity(0.92)
        default:
            return Color.white.opacity(0.94)
        }
    }
}

struct PickerOption: Identifiable {
    let id: String
    let title: String
}

enum PickerType: Identifiable {
    case appearance
    case weight

    var id: String {
        switch self {
        case .appearance: return "appearance"
        case .weight: return "weight"
        }
    }

    /// Supplies a title for the picker sheet.
    /// Change impact: Editing text changes how users interpret the selection context.
    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .weight: return "Weight Units"
        }
    }

    /// Supplies the available options for the picker.
    /// Change impact: Editing options changes what users can select for appearance or units.
    var options: [PickerOption] {
        switch self {
        case .appearance:
            return [
                PickerOption(id: "system", title: "System"),
                PickerOption(id: "light", title: "Light"),
                PickerOption(id: "dark", title: "Dark")
            ]
        case .weight:
            return [
                PickerOption(id: "lb", title: "Pounds (lb)"),
                PickerOption(id: "kg", title: "Kilograms (kg)")
            ]
        }
    }
}

#Preview {
    SettingsView(onDismiss: {})
}
