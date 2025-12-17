//
//  Haptics.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import UIKit

enum Haptics {
    /// Triggers a light tap feedback for primary taps.
    /// Change impact: Switching the impact style alters how Start/Finish taps feel system-wide.
    static func playLightTap() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// Triggers a medium tap feedback for brand or primary affordances.
    /// Change impact: Adjusting this style changes how brand presses feel globally.
    static func playMediumTap() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
}
