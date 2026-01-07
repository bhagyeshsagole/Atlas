//
//  SessionHistoryStackView.swift
//  Atlas
//
//  What this file is:
//  - Compact stack of recent sessions shown under the Home calendar, expandable on tap/drag.
//
//  Where it’s used:
//  - Embedded in `HomeView` to preview recent workouts.
//
//  Called from:
//  - Rendered inside `HomeView` just below the calendar using the recent sessions array.
//
//  Key concepts:
//  - Uses `@GestureState` to track drag distance and toggle between collapsed/expanded layouts.
//
//  Safe to change:
//  - Stack limit, spacing, or animation feel.
//
//  NOT safe to change:
//  - Removing haptic guard without considering double-fire; haptics could trigger repeatedly on drags.
//
//  Common bugs / gotchas:
//  - Forgetting to reset `hapticArmed` after a drag can disable future haptics.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Session History v1 — Pass 2
//

import SwiftUI
import SwiftData

struct SessionHistoryStackView: View {
    let sessions: [WorkoutSession]

    @State private var isExpanded = false // Controls whether cards are stacked or listed.
    @GestureState private var dragOffsetY: CGFloat = 0 // Tracks drag distance to decide toggle.
    @State private var hapticArmed = true // Prevents repeated haptic triggers during a drag.

    private let stackLimit = 3
    private let dragThreshold: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
            if isExpanded {
                expandedList
            } else {
                collapsedDeck
            }
        }
        .animation(AppMotion.primary, value: isExpanded)
        .frame(maxWidth: .infinity, minHeight: 140)
        .gesture(dragGesture)
        .onTapGesture {
            toggleExpansion(withHaptic: true)
        }
    }

    private var collapsedDeck: some View {
        let displaySessions = Array(sessions.prefix(stackLimit))
        return ZStack(alignment: .topLeading) {
            ForEach(displaySessions.indices, id: \.self) { index in
                SessionCardView(title: displaySessions[index].routineTitle)
                    .scaleEffect(1 - CGFloat(index) * 0.03)
                    .offset(y: CGFloat(index) * 10)
                    .opacity(1 - CGFloat(index) * 0.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppStyle.cardContentSpacing) {
                ForEach(sessions, id: \.id) { session in
                    SessionCardView(title: session.routineTitle)
                        .onTapGesture {
                            Haptics.playLightTap()
                        }
                }
            }
            .padding(.vertical, AppStyle.cardContentSpacing)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffsetY) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                if !isExpanded && value.translation.height < -dragThreshold {
                    toggleExpansion(withHaptic: true)
                } else if isExpanded && value.translation.height > dragThreshold {
                    toggleExpansion(withHaptic: true)
                }
                hapticArmed = true
            }
    }

    private func toggleExpansion(withHaptic: Bool) {
        isExpanded.toggle()
        if withHaptic, hapticArmed {
            Haptics.playLightTap()
            hapticArmed = false
        }
    }
}

private struct SessionCardView: View {
    let title: String
    private enum Metrics {
        static let cornerRadius: CGFloat = AppStyle.glassCardCornerRadiusLarge
        static let contentPadding: CGFloat = AppStyle.glassContentPadding
    }

    var body: some View {
        GlassCard(cornerRadius: Metrics.cornerRadius, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            Text(title)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.contentPadding)
        }
    }
}
