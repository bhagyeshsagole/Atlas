//
//  PressableGlassButtonStyle.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct PressableGlassButtonStyle: ButtonStyle {
    private let pressedScale: CGFloat = 0.97
    private let cornerRadius: CGFloat = 18
    private let baseStrokeOpacity: Double = 0.32
    private let pressedStrokeOpacity: Double = 0.55
    private let baseMaterialOpacity: Double = 0.26
    private let pressedMaterialOpacity: Double = 0.36

    /// Builds the pressable styling for glass buttons like Start Workout.
    /// Change impact: Tweaking `pressedScale`, stroke opacity, or material opacity instantly changes how the pill press feels everywhere.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(configuration.isPressed ? pressedMaterialOpacity : baseMaterialOpacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(configuration.isPressed ? pressedStrokeOpacity : baseStrokeOpacity), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .animation(AppMotion.primary, value: configuration.isPressed)
    }
}
