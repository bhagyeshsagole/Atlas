//
//  Haptics.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import UIKit

enum Haptics {
    /// VISUAL TWEAK: Change the `UIImpactFeedbackGenerator` style here to adjust the light tap feel.
    /// VISUAL TWEAK: Swap `.light`, `.medium`, or `.soft` to tune gentle taps across the app.
    static func playLightTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// VISUAL TWEAK: Change the `UIImpactFeedbackGenerator` style here to adjust brand/primary tap feel.
    /// VISUAL TWEAK: Swap `.medium`, `.heavy`, or `.rigid` to change press impact strength everywhere.
    static func playMediumTap() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
}
