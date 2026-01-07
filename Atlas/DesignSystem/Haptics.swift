//
//  Haptics.swift
//  Atlas
//
//  What this file is:
//  - Simple helper for playing light and medium haptic feedback across the app.
//
//  Where it’s used:
//  - Called by buttons and controls (e.g., Home gear button, start workout) to provide tap feedback.
//
//  Key concepts:
//  - `UIImpactFeedbackGenerator` triggers the vibration patterns; style controls intensity.
//
//  Safe to change:
//  - Swap feedback styles or add new helpers for different strengths.
//
//  NOT safe to change:
//  - Removing or renaming functions without updating call sites; taps would silently lose feedback.
//
//  Common bugs / gotchas:
//  - Haptics do nothing in Simulator; test on a device to feel changes.
//
//  DEV MAP:
//  - See: DEV_MAP.md → F) Popups / Menus / Haptics
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
