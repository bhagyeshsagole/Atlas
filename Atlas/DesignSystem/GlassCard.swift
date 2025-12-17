//
//  GlassCard.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
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
        cornerRadius: CGFloat = 24,
        shadowRadius: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.content = content
    }

    /// Draws the glass card with material, stroke, and shadow framing its content.
    /// Change impact: Adjust material or stroke opacity to change overall glass feel across screens.
    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
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
            .shadow(color: GlassStyle.dropShadow(for: colorScheme), radius: shadowRadius, x: 0, y: 12)
            .shadow(color: GlassStyle.ambientShadow(for: colorScheme), radius: 4, x: 0, y: 2)
    }
}

enum GlassStyle {
    /// Returns the glass background tuned per theme.
    /// Change impact: Adjusting opacity alters translucency across all glass surfaces.
    static func background(for colorScheme: ColorScheme) -> some ShapeStyle {
        .ultraThinMaterial.opacity(colorScheme == .dark ? 1.0 : 0.98)
    }

    /// Returns the outer stroke color for glass components.
    /// Change impact: Changing opacity alters border visibility across calendar and pills.
    static func outerStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.16)
    }

    /// Returns the inner highlight stroke for glass components.
    /// Change impact: Tweaking opacity adjusts perceived edge softness across glass surfaces.
    static func innerStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.25)
    }

    /// Returns the main drop shadow for depth.
    /// Change impact: Adjusting opacity or radius influences depth in light/dark modes.
    static func dropShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.26)
    }

    /// Returns an ambient secondary shadow for lift.
    /// Change impact: Adjusting opacity tunes softness of glass lift.
    static func ambientShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.04) : .black.opacity(0.08)
    }
}
