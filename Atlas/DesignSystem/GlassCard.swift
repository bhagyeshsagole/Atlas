//
//  GlassCard.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

struct GlassCard<Content: View>: View {
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
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: shadowRadius, x: 0, y: 12)
    }
}
