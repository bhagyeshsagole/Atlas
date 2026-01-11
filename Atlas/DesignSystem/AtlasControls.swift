//
//  AtlasControls.swift
//  Atlas
//
//  What this file is:
//  - Shared controls and sizing tokens for headers, pills, and glass menus.
//
//  Where it’s used:
//  - Buttons and pill rows across Home, Settings, routines, and history screens.
//
//  Called from:
//  - Adopted by views like `HomeView`, `RoutineListView`, `SettingsView`, and `WorkoutSessionView` for consistent controls.
//
//  Key concepts:
//  - View modifiers like `atlasGlassPill()` apply consistent glass styling.
//  - Central token structs keep tap targets and icon sizes consistent app-wide.
//
//  Safe to change:
//  - Sizing tokens, padding, or styling values when adjusting visuals.
//
//  NOT safe to change:
//  - Remove modifiers or token names without updating all controls; many views depend on them.
//
//  Common bugs / gotchas:
//  - Shrinking `headerButtonSize` below `tapTarget` makes icons harder to tap.
//  - Forgetting `.buttonStyle(.plain)` can reintroduce default blue button tint.
//
//  DEV MAP:
//  - See: DEV_MAP.md → E) Design System / UI Consistency
//

import SwiftUI

struct AtlasControlTokens {
    static let tapTarget: CGFloat = 44

    /// DEV MAP: Shared control sizing (header icons, pills, glass) lives here.
    /// VISUAL TWEAK: Change `headerButtonSize` to make Back/+ identical everywhere.
    static let headerButtonSize: CGFloat = 44
    /// VISUAL TWEAK: Change `headerIconSize` to scale all header icons.
    static let headerIconSize: CGFloat = 20
    /// VISUAL TWEAK: Change `headerIconWeight` to make header icons bolder/lighter.
    static let headerIconWeight: Font.Weight = .semibold

    /// VISUAL TWEAK: Change `pillHeightPrimary` to resize all primary CTA pills.
    static let pillHeightPrimary: CGFloat = 52
    /// VISUAL TWEAK: Change `pillHeightRow` to resize all routine pills.
    static let pillHeightRow: CGFloat = 64
    /// VISUAL TWEAK: Change `pillCornerRadius` to align rounding across pills/cards.
    static let pillCornerRadius: CGFloat = 18

    static let glassStrokeWidth: CGFloat = 1
    /// VISUAL TWEAK: Increase `glassStrokeOpacityLight` if borders disappear in light mode.
    static let glassStrokeOpacityLight: Double = 0.22
    static let glassStrokeOpacityDark: Double = 0.18
    /// VISUAL TWEAK: Raise `glassFillOpacityLight` if glass fades into white backgrounds.
    static let glassFillOpacityLight: Double = 0.16
    static let glassFillOpacityDark: Double = 0.22
    /// VISUAL TWEAK: Increase `shadowOpacityLight` to keep pills floating on white.
    static let shadowOpacityLight: Double = 0.2
    static let shadowOpacityDark: Double = 0.16
    static let shadowRadiusLight: CGFloat = 10
    static let shadowRadiusDark: CGFloat = 8
}

/// Glass modifier shared across pills, cards, and menus.
/// VISUAL TWEAK: Adjust opacity tokens to brighten or flatten glass across light/dark.
struct AtlasGlass: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let fillOpacity = isDark ? AtlasControlTokens.glassFillOpacityDark : AtlasControlTokens.glassFillOpacityLight
        let strokeOpacity = isDark ? AtlasControlTokens.glassStrokeOpacityDark : AtlasControlTokens.glassStrokeOpacityLight
        let shadowOpacity = isDark ? AtlasControlTokens.shadowOpacityDark : AtlasControlTokens.shadowOpacityLight
        let shadowRadius = isDark ? AtlasControlTokens.shadowRadiusDark : AtlasControlTokens.shadowRadiusLight

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isDark ? Color.white.opacity(strokeOpacity) : Color.black.opacity(strokeOpacity), lineWidth: AtlasControlTokens.glassStrokeWidth)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: AppStyle.dropShadowOffsetY / 1.5)
    }
}

extension View {
    func atlasGlassPill() -> some View {
        modifier(AtlasGlass(cornerRadius: AtlasControlTokens.pillCornerRadius))
    }

    func atlasGlassCard() -> some View {
        modifier(AtlasGlass(cornerRadius: AtlasControlTokens.pillCornerRadius))
    }

    func atlasGlassMenu() -> some View {
        modifier(AtlasGlass(cornerRadius: AtlasControlTokens.pillCornerRadius))
    }
}

/// Reusable header icon-only control with unified sizing and monochrome styling.
/// VISUAL TWEAK: Toggle glass backplate style for all header icons in one place.
struct AtlasHeaderIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    let isGlassBackplate: Bool
    let action: () -> Void

    init(systemName: String, isGlassBackplate: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.isGlassBackplate = isGlassBackplate
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .font(.system(size: AtlasControlTokens.headerIconSize, weight: AtlasControlTokens.headerIconWeight))
                .frame(width: AtlasControlTokens.headerButtonSize, height: AtlasControlTokens.headerButtonSize)
                .contentShape(Rectangle())
                .background {
                    if isGlassBackplate {
                        let isDark = colorScheme == .dark
                        let fillOpacity = isDark ? AtlasControlTokens.glassFillOpacityDark : AtlasControlTokens.glassFillOpacityLight
                        let strokeOpacity = isDark ? AtlasControlTokens.glassStrokeOpacityDark : AtlasControlTokens.glassStrokeOpacityLight
                        Circle()
                            .fill(.ultraThinMaterial.opacity(fillOpacity))
                            .overlay(
                                Circle()
                                    .stroke(isDark ? Color.white.opacity(strokeOpacity) : Color.black.opacity(strokeOpacity), lineWidth: AtlasControlTokens.glassStrokeWidth)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(max(0, (AtlasControlTokens.tapTarget - AtlasControlTokens.headerButtonSize) / 2))
    }
}

/// Primary CTA pill used for Start/Finish buttons across the app.
/// VISUAL TWEAK: Change `pillHeightPrimary` to resize all primary pills.
struct AtlasPillButton: View {
    let title: String
    let systemImage: String?
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: AppStyle.pillContentSpacing) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: AppStyle.pillImageSize, weight: AppStyle.pillWeight))
                }
                Text(title)
                    .appFont(.pill, weight: .semibold)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: AtlasControlTokens.pillHeightPrimary)
        }
        .buttonStyle(.plain)
        .atlasGlassPill()
    }
}

/// Shared pill/card shell for rows (routines, settings rows, list cards).
/// VISUAL TWEAK: Use `pillHeightRow`/`pillCornerRadius` to align all row pills.
struct AtlasRowPill<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.glassContentPadding)
            .frame(minHeight: AtlasControlTokens.pillHeightRow, alignment: .leading)
            .atlasGlassCard()
    }
}

/// Centered compact menu for edit/delete flows with shared glass styling.
/// VISUAL TWEAK: Adjust menu padding/width so it’s tight and never huge.
struct AtlasCompactCenterMenu<Content: View>: View {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    init(isPresented: Bool, onDismiss: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        if isPresented {
            ZStack {
                // Transparent overlay to catch taps for dismissal without dimming the background.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    content
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .atlasGlassMenu()
                .frame(maxWidth: AppStyle.popupMaxWidth)
                Button("Cancel") {
                    onDismiss()
                }
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.secondary)
                }
                .padding()
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .animation(AppStyle.popupAnimation, value: isPresented)
            }
        }
    }
}
