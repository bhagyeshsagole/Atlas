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
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 12)
            .shadow(color: ambientShadow, radius: 4, x: 0, y: 2)
    }

    private var strokeColor: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.18)
        default:
            return .black.opacity(0.12)
        }
    }

    private var shadowColor: Color {
        switch colorScheme {
        case .dark:
            return .black.opacity(0.28)
        default:
            return .black.opacity(0.22)
        }
    }

    private var ambientShadow: Color {
        switch colorScheme {
        case .dark:
            return .white.opacity(0.04)
        default:
            return .black.opacity(0.06)
        }
    }
}
