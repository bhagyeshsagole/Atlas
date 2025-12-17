//
//  HomeView.swift
//  Atlas
//
//  Created by Codex on 2/12/24
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @Query(sort: [SortDescriptor(\Workout.date, order: .reverse)]) private var workouts: [Workout]
    private let calendar = Calendar.current

    let startWorkout: () -> Void
    let openSettings: () -> Void

    @State private var showCalendarCard = false
    @State private var showStartButton = false

    /// Builds the Home screen with the glass calendar, settings toggle, and Start Workout pill.
    /// Change impact: Tweaking layout constants or reveal state timing shifts the feel of the entrance and spacingg.
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    // Top bar: brand label and settings button aligned to one row.
                    HStack {
                        Button {
                            onAtlasTap()
                        } label: {
                            /// VISUAL TWEAK: Change `AppStyle.brandBaseSize` or `AppStyle.fontBump` to make "Atlas" bigger/smaller.
                            /// VISUAL TWEAK: Toggle `AppStyle.brandItalic` if you don’t want italics on the brand.
                            /// VISUAL TWEAK: Update `.foregroundStyle(.primary)` to change monochrome color rules.
                            /// VISUAL TWEAK: Adjust `AppStyle.brandPaddingHorizontal`/`brandPaddingVertical` or HStack alignment to change header spacing.
                            /// VISUAL TWEAK: Change haptic style in `onAtlasTap()`.
                            Text("Atlas")
                                .appFont(.brand)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, AppStyle.brandPaddingHorizontal)
                                .padding(.vertical, AppStyle.brandPaddingVertical)
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
                                .appFont(.section, weight: .semibold)
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.primary)
                                .padding(AppStyle.headerIconHitArea)
                                .background(
                                    RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                        .fill(.white.opacity(isDarkAppearance ? AppStyle.headerButtonFillOpacityDark : AppStyle.headerButtonFillOpacityLight))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppStyle.dropdownCornerRadius)
                                        .stroke(.white.opacity(AppStyle.headerButtonStrokeOpacity), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)
                    }
                    .padding(.top, AppStyle.headerTopPadding)
                    .tint(.primary)

                    // Calendar card: adjust `AppStyle.glassCardCornerRadiusLarge`/`glassShadowRadiusPrimary`; animations rely on `AppMotion.primary`.
                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                            // Month header row: `AppStyle.calendarHeaderSpacing` controls spacing between labels and badges.
                            HStack(spacing: AppStyle.calendarHeaderSpacing) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentMonthTitle)
                                        .appFont(.title, weight: .semibold)
                                        .foregroundStyle(.primary)
                                }
                            }

                            // Weekday labels row.
                            HStack {
                                ForEach(shortWeekdays, id: \.self) { symbol in
                                    Text(symbol)
                                        .appFont(.body, weight: .medium)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            // Month grid: adjust `AppStyle.calendarGridSpacing` to change vertical/horizontal padding between days.
                            LazyVGrid(columns: gridColumns, spacing: AppStyle.calendarGridSpacing) {
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
                    .offset(y: showCalendarCard ? 0 : AppStyle.cardRevealOffset)
                    .padding(.top, AppStyle.screenTopPadding)
                    .animation(AppMotion.primary, value: showCalendarCard)

                    Spacer(minLength: AppStyle.homeBottomSpacer)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding)
                .padding(.bottom, AppStyle.homeBottomInset)
            }
            .scrollIndicators(.hidden)

            // Start Workout pill pinned near bottom: press feel driven by `PressableGlassButtonStyle` constants.
            Button {
                Haptics.playLightTap()
                startWorkout()
            } label: {
                Text("Start Workout")
                    .appFont(.pill, weight: .semibold)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PressableGlassButtonStyle())
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.bottom, AppStyle.startButtonBottomPadding)
            .opacity(showStartButton ? 1 : 0)
            .offset(y: showStartButton ? 0 : AppStyle.startButtonHiddenOffset)
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
        Array(repeating: GridItem(.flexible(), spacing: AppStyle.calendarColumnSpacing), count: 7)
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
        HomeView.monthFormatter.string(from: Date())
    }

    /// Builds the adaptive background gradient for light/dark.
    /// Change impact: Tweaking colors here shifts the overall page mood in both themes.
    private var backgroundGradient: LinearGradient {
        /// VISUAL TWEAK: Change the opacity pairs below to brighten or darken the Home background gradient.
        /// VISUAL TWEAK: Swap the gradient colors to retune the light/dark atmosphere across the screen.
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    /// VISUAL TWEAK: Change the haptic call here to adjust brand tap feel.
    /// VISUAL TWEAK: Swap `Haptics.playMediumTap()` for another style to change the press feedback.
    private func onAtlasTap() {
        Haptics.playMediumTap()
    }

    /// Resolves whether the appearance should be dark based on stored mode and system fallback.
    /// Change impact: Adjusting logic here affects gradients and button fills on Home.
    private var isDarkAppearance: Bool {
        appearanceMode == "dark"
    }
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
                    .appFont(.body, weight: isToday ? .semibold : .regular)
                    .foregroundStyle(.primary.opacity(isToday ? AppStyle.calendarDayTextOpacityToday : AppStyle.calendarDayTextOpacityDefault))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppStyle.calendarDayVerticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: AppStyle.calendarDayCornerRadius)
                            .fill(.white.opacity(isToday ? AppStyle.calendarDayHighlightOpacity : 0.0))
                    )
            } else {
                Color.clear
                    .frame(height: AppStyle.calendarTodayHeight)
            }

            if hasWorkout {
                Circle()
                    .fill(.white)
                    .frame(width: AppStyle.calendarWorkoutDotSize, height: AppStyle.calendarWorkoutDotSize)
                    .transition(AppMotion.bubbleTransition)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppStyle.calendarDayMinHeight)
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
