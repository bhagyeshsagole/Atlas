//
//  HomeView.swift
//  Atlas
//
//  Created by Codex on 2/12/24.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\Workout.date, order: .reverse)]) private var workouts: [Workout]
    private let calendar = Calendar.current
    private let cardCornerRadius: CGFloat = 26
    private let cardShadowRadius: CGFloat = 18
    private let gridSpacing: CGFloat = 10
    private let headerSpacing: CGFloat = 8

    let startWorkout: () -> Void
    let openSettings: () -> Void

    @State private var showCalendarCard = false
    @State private var showStartButton = false
    @State private var isBrandPressed = false
    @Namespace private var brandNamespace

    /// Builds the Home screen with the glass calendar, settings toggle, and Start Workout pill.
    /// Change impact: Tweaking layout constants or reveal state timing shifts the feel of the entrance and spacing.
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Top bar: brand label and settings button aligned to one row.
                    HStack {
                        Button {
                            triggerBrandPulse()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 44, height: 44)
                                    .scaleEffect(isBrandPressed ? 1.0 : 0.001)
                                    .opacity(isBrandPressed ? 1.0 : 0.0)
                                    .animation(reduceMotion ? .easeOut(duration: 0.2) : AppMotion.primary, value: isBrandPressed)
                                    .matchedGeometryEffect(id: "brandBadge", in: brandNamespace)

                                Text("Atlas")
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .matchedGeometryEffect(id: "brandText", in: brandNamespace)
                                    .padding(.horizontal, 4)
                            }
                            .frame(height: 44, alignment: .center)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            assert(Thread.isMainThread, "openSettings should run on main thread")
                            Haptics.playLightTap()
                            openSettings()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.headline.weight(.semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(.white.opacity(isDarkAppearance ? 0.12 : 0.16))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)
                    }
                    .padding(.top, 6)
                    .tint(.primary)

                    // Calendar card: adjust `cardCornerRadius`/`cardShadowRadius`; animations rely on `AppMotion.primary`.
                    GlassCard(cornerRadius: cardCornerRadius, shadowRadius: cardShadowRadius) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Month header row: `headerSpacing` controls spacing between labels and badges.
                            HStack(spacing: headerSpacing) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentMonthTitle)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                            }

                            // Weekday labels row.
                            HStack {
                                ForEach(shortWeekdays, id: \.self) { symbol in
                                    Text(symbol)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            // Month grid: adjust `gridSpacing` to change vertical/horizontal padding between days.
                            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                                    DayCell(
                                        date: date,
                                        calendar: calendar,
                                        isToday: isToday(date),
                                        hasWorkout: hasWorkout(on: date)
                                    )
                                }
                            }
                        }
                    }
                    .opacity(showCalendarCard ? 1 : 0)
                    .offset(y: showCalendarCard ? 0 : 8)
                    .padding(.top, 12)
                    .animation(AppMotion.primary, value: showCalendarCard)

                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 160)
            }

            // Start Workout pill pinned near bottom: press feel driven by `PressableGlassButtonStyle` constants.
            Button {
                Haptics.playLightTap()
                startWorkout()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .font(.headline.weight(.semibold))
                    Text("Start Workout")
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(PressableGlassButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .opacity(showStartButton ? 1 : 0)
            .offset(y: showStartButton ? 0 : 10)
            .animation(AppMotion.primary.delay(0.06), value: showStartButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundGradient)
        .tint(.primary)
        .onAppear {
            withAnimation(AppMotion.primary) {
                showCalendarCard = true
            }
            withAnimation(AppMotion.primary.delay(0.05)) {
                showStartButton = true
            }
        }
    }

    /// Builds the grid columns for a 7-day calendar.
    /// Change impact: Changing count or spacing reshapes the grid and day sizing.
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    /// Builds the month grid with leading offsets to align weekdays.
    /// Change impact: Adjust date math here to shift which days appear and how the grid anchors.
    private var monthGrid: [Date?] {
        guard let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: Date())
        ) else { return [] }

        let range = calendar.range(of: .day, in: .month, for: startOfMonth) ?? 1..<32
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        return days
    }

    /// Builds a set of normalized dates that have workouts.
    /// Change impact: Changing normalization alters which cells show bubbles (e.g., time-zone shifts).
    private var workoutDays: Set<Date> {
        Set(workouts.map { calendar.startOfDay(for: $0.date) })
    }

    /// Formats the current month name for the header.
    /// Change impact: Changing the formatter impacts month title styling and localization.
    private var currentMonthTitle: String {
        Self.monthFormatter.string(from: Date())
    }

    /// Builds the adaptive background gradient for light/dark.
    /// Change impact: Tweaking colors here shifts the overall page mood in both themes.
    private var backgroundGradient: LinearGradient {
        if appearanceMode == "dark" {
            return LinearGradient(
                colors: [
                    Color.black.opacity(0.92),
                    Color.black.opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    Color.white.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Builds weekday symbols aligned to the system calendar.
    /// Change impact: Changing `shortWeekdaySymbols` impacts how week rows label each column.
    private var shortWeekdays: [String] {
        var symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        if first > 0 {
            symbols = Array(symbols[first...] + symbols[..<first])
        }
        return symbols
    }

    /// Determines if a given date should show a workout bubble.
    /// Change impact: Updating this logic changes when bubbles animate in/out on the calendar.
    private func hasWorkout(on date: Date?) -> Bool {
        guard let date else { return false }
        let normalized = calendar.startOfDay(for: date)
        return workoutDays.contains(normalized)
    }

    /// Determines if the date is today for styling.
    /// Change impact: Altering the comparison changes which cell gets the "today" highlight.
    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return calendar.isDateInToday(date)
    }

    /// Resolves whether the appearance should be dark based on stored mode and system fallback.
    /// Change impact: Adjusting logic here affects gradients and button fills on Home.
    private var isDarkAppearance: Bool {
        appearanceMode == "dark"
    }

    /// Triggers the brand morph animation with haptic feedback.
    /// Change impact: Adjusting timings changes how the brand pulse feels.
    private func triggerBrandPulse() {
        guard !isBrandPressed else { return }
        assert(Thread.isMainThread, "Brand pulse should run on main thread")
        Haptics.playMediumTap()
        let animation = reduceMotion ? Animation.easeOut(duration: 0.2) : AppMotion.primary
        withAnimation(animation) {
            isBrandPressed = true
        }
        let delay = reduceMotion ? 0.2 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(animation) {
                isBrandPressed = false
            }
        }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

struct DayCell: View {
    let date: Date?
    let calendar: Calendar
    let isToday: Bool
    let hasWorkout: Bool

    /// Builds a day cell with a number label and animated workout bubble.
    /// Change impact: Adjusting text or bubble sizing affects readability and animation subtlety in the grid.
    var body: some View {
        VStack(spacing: 6) {
            if let date {
                Text(dayString(for: date))
                    .font(isToday ? .body.weight(.semibold) : .body.weight(.regular))
                    .foregroundStyle(.primary.opacity(isToday ? 0.95 : 0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(isToday ? 0.12 : 0.0))
                    )
            } else {
                Color.clear
                    .frame(height: 32)
            }

            if hasWorkout {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .transition(AppMotion.bubbleTransition)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .animation(AppMotion.primary, value: hasWorkout)
    }

    /// Formats the numeric day string for the cell.
    /// Change impact: Adjusting formatting changes how the grid numbers render (e.g., leading zeros).
    private func dayString(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }
}

#Preview {
    HomeView(
        startWorkout: {},
        openSettings: {}
    )
    .modelContainer(for: Workout.self, inMemory: true)
}
