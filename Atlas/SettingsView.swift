//
//  SettingsView.swift
//  Atlas
//
//  What this file is:
//  - Full-screen settings page for appearance mode and weight unit preferences.
//
//  Where it’s used:
//  - Presented as a fullScreenCover from Home/ContentView when the gear icon is tapped.
//
//  Called from:
//  - Shown via `ContentView` fullScreenCover when the Home gear button triggers `openSettings`.
//
//  Key concepts:
//  - `@AppStorage` saves choices in UserDefaults so the app remembers them next launch.
//  - Uses dropdown state to toggle open/closed option lists.
//
//  Safe to change:
//  - Copy, spacing, or add new rows/options.
//
//  NOT safe to change:
//  - Removing the dismiss callbacks; Home relies on this view closing itself when selections change.
//
//  Common bugs / gotchas:
//  - Leaving `activeDropdown` non-nil traps taps; always close dropdowns on background tap.
//  - Forgetting to sync `weightUnit` with other screens will desync unit conversions.
//
//  DEV MAP:
//  - See: DEV_MAP.md → F) Popups / Menus / Haptics
//
import SwiftUI
import Supabase

struct SettingsView: View {
    let onDismiss: () -> Void
    @AppStorage("appearanceMode") private var appearanceMode = "light" // Saved user preference for light/dark.
    @AppStorage("weightUnit") private var weightUnit: String = "lb" // Shared across screens for weight formatting.
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore
    @State private var activeDropdown: DropdownType? // Tracks which dropdown is open.
    @State private var showingAccount = false

    /// Builds the full-screen settings page with monochrome appearance controls.
    /// Change impact: Adjusting layout, card fills, or typography changes the calm, premium feel of the settings experience.
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    SettingsHeaderBar(title: "Settings", onDismiss: onDismiss)
                        .padding(.top, AppStyle.headerTopPadding)

                    // Appearance selector via shared dropdown menu.
                    SettingsSectionLabel(text: "APPEARANCE")
                    SettingsGroupCard {
                        SettingsDropdownRow(
                            title: "Appearance",
                            value: appearanceLabel,
                            selectedID: appearanceMode,
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
                            selectedID: weightUnit,
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
                    if let instagramURL = URL(string: "https://www.instagram.com/bhagyeshsagole?igsh=bndhaGx6c3loMnZ3") {
                        SettingsGroupCard {
                            Link(destination: instagramURL) {
                                HStack {
                                    Text("Tag & Explore @BhagyeshSagole")
                                        .appFont(.body, weight: .semibold)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }

                    // Account / auth debug entry point.
                    SettingsSectionLabel(text: "ACCOUNT")
                    SettingsGroupCard {
                        SettingsRow(
                            title: "Account (Beta)",
                            value: authStore.isAuthenticated ? "Signed in" : "Not signed in",
                            showsChevron: true,
                            action: { showingAccount = true }
                        )
                    }

                    #if DEBUG
                    SettingsSectionLabel(text: "DEBUG")
                    SettingsGroupCard {
                        SettingsRow(
                            title: "Session Status",
                            value: debugSessionStatus,
                            showsChevron: false,
                            action: {}
                        )
                        SettingsRow(
                            title: "Access Token Present",
                            value: debugTokenPresent,
                            showsChevron: false,
                            action: {}
                        )
                        SettingsRow(
                            title: "Debug: Print Auth Session",
                            value: nil,
                            showsChevron: false,
                            action: debugPrintAuthSession
                        )
                    }
                    #endif

                    Spacer(minLength: AppStyle.settingsBottomPadding)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
            }
        }
        .tint(.primary)
        .fullScreenCover(isPresented: $showingAccount) {
            AccountView()
                .environmentObject(authStore)
        }
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
        /// VISUAL TWEAK: Change `AppStyle.settingsBackgroundOpacityLight`/`Dark` to brighten or darken the Settings backdrop.
        /// VISUAL TWEAK: Swap the base `Color.black`/`Color.white` if you want a different base hue.
        appearanceMode == "dark" ? Color.black.opacity(AppStyle.settingsBackgroundOpacityDark) : Color.white.opacity(AppStyle.settingsBackgroundOpacityLight)
    }

    #if DEBUG
    private var debugSessionStatus: String {
        if let session = authStore.session {
            let prefix = session.user.id.uuidString.prefix(8)
            let clientId = authStore.supabaseClient.map { Unmanaged.passUnretained($0 as AnyObject).toOpaque() }
            return "Signed In (\(prefix)... | client=\(clientId.map { "\($0)" } ?? "nil"))"
        }
        return "Signed Out"
    }

    private var debugTokenPresent: String {
        let token = authStore.session?.accessToken ?? authStore.supabaseClient?.auth.currentSession?.accessToken
        return (token?.isEmpty == false) ? "Yes" : "No"
    }

    private func debugPrintAuthSession() {
        let session = authStore.supabaseClient?.auth.currentSession
        let userId = session?.user.id.uuidString ?? "nil"
        let hasSession = session != nil
        print("[DEBUG][AUTH] session_present=\(hasSession) user_id=\(userId)")
    }
    #endif

}

struct SettingsHeaderBar: View {
    let title: String
    let onDismiss: () -> Void

    /// Builds the top bar with dismiss X and centered title.
    /// Change impact: Adjusting padding or icon styling alters perceived density and hierarchy of the header.
    var body: some View {
        HStack(spacing: AppStyle.settingsHeaderSpacing) {
            AtlasHeaderIconButton(systemName: "xmark", isGlassBackplate: true, action: onDismiss)
            Spacer()
            /// VISUAL TWEAK: Change `AppStyle.titleBaseSize` or `AppStyle.fontBump` to resize the Settings title.
            /// VISUAL TWEAK: Adjust `AppStyle.settingsHeaderSpacing` or header chip fill opacities to change header density.
            Text(title)
                .appFont(.title, weight: .semibold)
                .foregroundStyle(.primary)
            Spacer()
            Color.clear.frame(width: AtlasControlTokens.headerButtonSize)
        }
    }
}

struct SettingsSectionLabel: View {
    let text: String

    /// Renders a compact uppercase section label in secondary tone.
    /// Change impact: Adjusting font or opacity shifts perceived grouping strength.
    var body: some View {
        /// VISUAL TWEAK: Change `AppStyle.sectionBaseSize` or `AppStyle.fontBump` to resize section labels.
        /// VISUAL TWEAK: Toggle `AppStyle.sectionLetterCaseUppercased` to switch casing for all section headers.
        Text(text)
            .appFont(.section, weight: .bold)
            .foregroundStyle(.secondary)
            .textCase(AppStyle.sectionLetterCaseUppercased ? .uppercase : .none)
            .padding(.horizontal, 4)
    }
}

struct SettingsGroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    /// Wraps rows in a glass-like card with subtle stroke and shadow.
    /// Change impact: Tweaking corner radius or fill opacity changes the sense of depth across all settings groups.
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            content
        }
        .padding(AppStyle.settingsGroupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasGlassCard()
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
            HStack(spacing: AppStyle.rowSpacing) {
                /// VISUAL TWEAK: Change `AppStyle.bodyBaseSize` or `AppStyle.fontBump` to adjust row label size.
                /// VISUAL TWEAK: Adjust `AppStyle.rowSpacing` to change spacing between label and trailing accessories.
                Text(title)
                    .appFont(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if let value {
                    Text(value)
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .appFont(.caption, weight: .semibold)
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
    let selectedID: String
    let isOpen: Bool
    let options: [MenuOption]
    let onTap: () -> Void
    let onSelect: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Provides a stable row that triggers a trailing dropdown without hiding label/value.
    /// Change impact: Adjusting fonts or padding changes the touch target feel for all dropdowns.
    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onTap) {
                HStack(spacing: AppStyle.rowSpacing) {
                    /// VISUAL TWEAK: Change `AppStyle.bodyBaseSize` or `AppStyle.fontBump` to resize dropdown labels.
                    /// VISUAL TWEAK: Adjust `AppStyle.rowSpacing`/`AppStyle.rowValueSpacing` to tighten or relax label/value spacing.
                    Text(title)
                        .appFont(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: AppStyle.rowValueSpacing) {
                        Text(value)
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(isOpen ? 0 : 1)
                    .allowsHitTesting(!isOpen)
                    .animation(.easeInOut(duration: AppStyle.shortAnimationDuration), value: isOpen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                DropdownMenuView(options: options, selectedID: selectedID, onSelect: onSelect)
                    .frame(maxWidth: AppStyle.dropdownWidth, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, AppStyle.dropdownTrailingPadding)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    .animation(reduceMotion ? .easeOut(duration: AppStyle.shortAnimationDuration) : AppMotion.primary, value: isOpen)
            }
        }
    }
}

struct DropdownMenuView: View {
    let options: [MenuOption]
    let selectedID: String
    let onSelect: (String) -> Void

    /// Renders the compact trailing dropdown menu with glass styling.
    /// Change impact: Adjusting corner radius or opacity changes perceived depth for all dropdowns.
    var body: some View {
        /// VISUAL TWEAK: Change `AppStyle.dropdownRowSpacing`/padding constants to tighten or loosen the menu list.
        /// VISUAL TWEAK: Change `AppStyle.dropdownCornerRadius`/`dropdownFillOpacity` to alter dropdown glass styling.
        VStack(alignment: .leading, spacing: AppStyle.dropdownRowSpacing) {
            ForEach(options) { option in
                Button {
                    onSelect(option.id)
                } label: {
                    HStack {
                        Text(option.title)
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.primary)
                        Spacer()
                        if option.id == selectedID {
                            Image(systemName: "checkmark")
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppStyle.dropdownRowHorizontalPadding)
                    .padding(.vertical, AppStyle.dropdownRowVerticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: AppStyle.dropdownRowCornerRadius)
                            .fill(Color.white.opacity(AppStyle.dropdownRowFillOpacity))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppStyle.dropdownMenuPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                .fill(Color.white.opacity(AppStyle.dropdownFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                .stroke(Color.white.opacity(AppStyle.dropdownStrokeOpacity), lineWidth: 1)
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
