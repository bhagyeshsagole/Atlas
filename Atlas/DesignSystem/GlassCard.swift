//
//  GlassCard.swift
//  Atlas
//
//  Overview: Reusable glass card container with shared styling.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat
    private let shadowRadius: CGFloat
    private let content: () -> Content

    /// Builds a reusable glass container with consistent corner radius and stroke.
    /// Change impact: Tweaking `cornerRadius` or `shadowRadius` here shifts the depth of every card (calendar).
    init(
        cornerRadius: CGFloat = AppStyle.glassCardCornerRadiusLarge,
        shadowRadius: CGFloat = AppStyle.glassShadowRadiusPrimary,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.content = content
    }

    /// Draws the glass card with material, stroke, and shadow framing its content.
    /// Change impact: Adjust material or stroke opacity to change overall glass feel across screens.
    var body: some View {
        /// VISUAL TWEAK: Change `AppStyle.glassCardCornerRadiusLarge` or `AppStyle.glassContentPadding` to reshape cards.
        /// VISUAL TWEAK: Adjust `AppStyle.glassShadowRadiusPrimary` or shadow opacities to alter perceived depth.
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.glassContentPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(GlassStyle.background(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GlassStyle.outerStroke(for: colorScheme), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GlassStyle.innerStroke(for: colorScheme), lineWidth: 0.6)
            )
            .shadow(color: GlassStyle.dropShadow(for: colorScheme), radius: shadowRadius, x: 0, y: AppStyle.dropShadowOffsetY)
            .shadow(color: GlassStyle.ambientShadow(for: colorScheme), radius: AppStyle.dropShadowAmbientRadius, x: 0, y: AppStyle.ambientShadowOffsetY)
    }
}

enum GlassStyle {
    /// Returns the glass background tuned per theme.
    /// Change impact: Adjusting opacity alters translucency across all glass surfaces.
    static func background(for colorScheme: ColorScheme) -> some ShapeStyle {
        .ultraThinMaterial.opacity(colorScheme == .dark ? AppStyle.glassBackgroundOpacityDark : AppStyle.glassBackgroundOpacityLight)
    }

    /// Returns the outer stroke color for glass components.
    /// Change impact: Changing opacity alters border visibility across calendar and pills.
    static func outerStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(AppStyle.glassStrokeOpacityDark) : .black.opacity(AppStyle.glassStrokeOpacityLight)
    }

    /// Returns the inner highlight stroke for glass components.
    /// Change impact: Tweaking opacity adjusts perceived edge softness across glass surfaces.
    static func innerStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(AppStyle.glassInnerStrokeOpacityDark) : .white.opacity(AppStyle.glassInnerStrokeOpacityLight)
    }

    /// Returns the main drop shadow for depth.
    /// Change impact: Adjusting opacity or radius influences depth in light/dark modes.
    static func dropShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(AppStyle.glassDropShadowOpacityDark) : .black.opacity(AppStyle.glassDropShadowOpacityLight)
    }

    /// Returns an ambient secondary shadow for lift.
    /// Change impact: Adjusting opacity tunes softness of glass lift.
    static func ambientShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(AppStyle.glassAmbientShadowOpacityDark) : .black.opacity(AppStyle.glassAmbientShadowOpacityLight)
    }
}
