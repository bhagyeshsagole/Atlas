//
//  PressableGlassButtonStyle.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct PressableGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let pressedScale: CGFloat = 0.97
    private let cornerRadius: CGFloat = 18

    /// Builds the pressable styling for glass buttons like Start Workout.
    /// Change impact: Tweaking `pressedScale`, stroke opacity, or material opacity instantly changes how the pill press feels everywhere.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
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
