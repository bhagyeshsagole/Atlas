//
//  AppMotion.swift
//  Atlas
//
//  What this file is:
//  - Shared animation curves for presses, reveals, and transitions.
//
//  Where it’s used:
//  - Referenced by buttons, cards, and overlays for consistent spring motion.
//
//  Key concepts:
//  - Returning `Animation` statics keeps timing consistent; swapping values tweaks all animations at once.
//
//  Safe to change:
//  - Spring tuning numbers or transition combinations to adjust feel.
//
//  NOT safe to change:
//  - Removing `primary` or `bubbleTransition` without updating every caller; animations would break.
//
//  Common bugs / gotchas:
//  - Setting a very stiff spring can make animations feel jittery; test on device.
//
//  DEV MAP:
//  - See: DEV_MAP.md → E) Design System / UI Consistency
//

import SwiftUI

enum AppMotion {
    /// Builds the primary animation curve used for all UI motion.
    /// Change impact: Tuning duration or bounce here retunes every animation and press response in the app.
    static var primary: Animation {
        if #available(iOS 17.0, *) {
            return .interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.12)
        } else {
            return .interpolatingSpring(stiffness: 300, damping: 26)
        }
    }

    /// Builds a compact scale+opacity transition for small elements like bubbles.
    /// Change impact: Adjusting scale or opacity tweaks how the workout bubble appears/disappears.
    static var bubbleTransition: AnyTransition {
        .scale(scale: 0.86).combined(with: .opacity)
    }
}
