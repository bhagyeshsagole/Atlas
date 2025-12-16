//
//  AppMotion.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI

enum AppMotion {
    /// Builds the primary animation curve used for all UI motion.
    /// Change impact: Tuning duration or bounce here retunes every animation and press response in the app.
    static var primary: Animation {
        if #available(iOS 17.0, *) {
            return .snappy(duration: 0.24, extraBounce: 0.08)
        } else {
            return .interpolatingSpring(stiffness: 320, damping: 26)
        }
    }

    /// Builds a compact scale+opacity transition for small elements like bubbles.
    /// Change impact: Adjusting scale or opacity tweaks how the workout bubble appears/disappears.
    static var bubbleTransition: AnyTransition {
        .scale(scale: 0.86).combined(with: .opacity)
    }
}
