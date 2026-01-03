//
//  PressableGlassButtonStyle.swift
//  Atlas
//
//  Overview: Button style for glass CTA pills shared across the app.
//

import SwiftUI

struct PressableGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let pressedScale: CGFloat = AppStyle.glassButtonPressedScale
    private let cornerRadius: CGFloat = AppStyle.glassButtonCornerRadius

    /// Builds the pressable styling for glass buttons like Start Workout.
    /// Change impact: Tweaking `pressedScale`, stroke opacity, or material opacity instantly changes how the pill press feels everywhere.
    func makeBody(configuration: Configuration) -> some View {
        /// VISUAL TWEAK: Change `AppStyle.glassButtonPressedScale` to deepen or soften the press animation.
        /// VISUAL TWEAK: Adjust `AppStyle.glassButtonCornerRadius` or padding constants to reshape all pills.
        configuration.label
            .padding(.vertical, AppStyle.glassButtonVerticalPadding)
            .padding(.horizontal, AppStyle.glassButtonHorizontalPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(GlassStyle.background(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GlassStyle.outerStroke(for: colorScheme).opacity(configuration.isPressed ? 1.0 : 0.9), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GlassStyle.innerStroke(for: colorScheme).opacity(configuration.isPressed ? 1.0 : 0.9), lineWidth: 0.6)
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .animation(AppMotion.primary, value: configuration.isPressed)
    }
}
