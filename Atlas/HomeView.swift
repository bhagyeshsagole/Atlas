//
//  HomeView.swift
//  Atlas
//
//  Overview: Home screen with calendar, brand header, and start workout entry point.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @Query(sort: [SortDescriptor(\Workout.date, order: .reverse)]) private var workouts: [Workout]
    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]) private var historySessions: [WorkoutSession]
    private let calendar = Calendar.current

    let startWorkout: () -> Void
    let openSettings: () -> Void

    @State private var showCalendarCard = false
    @State private var showStartButton = false
    @State private var isHistoryPresented = false
    @State private var isDayHistoryPresented = false
    @State private var selectedDayForHistory: Date = Date()

    /// Builds the Home screen with the glass calendar, settings toggle, and Start Workout pill.
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    // Top bar
                    HStack {
                        Button {
                            onAtlasTap()
                        } label: {
                            Text("Atlas")
                                .appFont(.brand)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, AppStyle.brandPaddingHorizontal)
                                .padding(.vertical, AppStyle.brandPaddingVertical)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        AtlasHeaderIconButton(systemName: "gearshape") {
                            assert(Thread.isMainThread, "openSettings should run on main thread")
                            Haptics.playLightTap()
                            openSettings()
                        }
                    }
                    .padding(.top, AppStyle.headerTopPadding)
                    .tint(.primary)

                    // Calendar card
                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                            HStack(spacing: AppStyle.calendarHeaderSpacing) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentMonthTitle)
                                        .appFont(.title, weight: .semibold)
                                        .foregroundStyle(.primary)
                                }
                            }

                            HStack {
                                ForEach(shortWeekdays, id: \.self) { symbol in
                                    Text(symbol)
                                        .appFont(.body, weight: .medium)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            LazyVGrid(columns: gridColumns, spacing: AppStyle.calendarGridSpacing) {
                                ForEach(Array(monthGrid.enumerated()), id: \.offset) { _, date in
                                    DayCell(
                                        date: date,
                                        calendar: calendar,
                                        isToday: isToday(date),
                                        hasWorkout: hasWorkout(on: date),
                                        hasSession: hasSession(on: date)
                                    ) { tappedDate in
                                        handleDaySelection(tappedDate)
                                    }
                                }
                            }
                        }
                    }
                    .opacity(showCalendarCard ? 1 : 0)
                    .offset(y: showCalendarCard ? 0 : AppStyle.cardRevealOffset)
                    .padding(.top, AppStyle.screenTopPadding)
                    .animation(AppMotion.primary, value: showCalendarCard)

                    sessionDeckSection
                        .padding(.top, AppStyle.cardContentSpacing)

                    Spacer(minLength: AppStyle.homeBottomSpacer)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding)
                .padding(.bottom, AppStyle.homeBottomInset)
            }
            .scrollIndicators(.hidden)

            // Start Workout pill
            AtlasPillButton("Start Workout") {
                Haptics.playLightTap()
                startWorkout()
            }
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
        .navigationDestination(isPresented: $isHistoryPresented) {
            AllHistoryView()
        }
        .navigationDestination(isPresented: $isDayHistoryPresented) {
            DayHistoryView(day: selectedDayForHistory)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppStyle.calendarColumnSpacing), count: 7)
    }

    private var monthGrid: [Date?] {
        let startOfMonth = currentMonthStart
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

    private var workoutDays: Set<Date> {
        Set(workouts.map { calendar.startOfDay(for: $0.date) })
    }

    private var activeSessionDays: Set<Date> {
        let days = historySessions
            .filter { $0.totalSets > 0 && $0.endedAt != nil }
            .map { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) }
        return Set(days)
    }

    private var currentMonthTitle: String {
        HomeView.monthFormatter.string(from: currentMonthStart)
    }

    private var currentMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

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

    private var shortWeekdays: [String] {
        var symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        if first > 0 {
            symbols = Array(symbols[first...] + symbols[..<first])
        }
        return symbols
    }

    private func hasWorkout(on date: Date?) -> Bool {
        guard let date else { return false }
        let normalized = calendar.startOfDay(for: date)
        return workoutDays.contains(normalized)
    }

    private func hasSession(on date: Date?) -> Bool {
        guard let date else { return false }
        let normalized = calendar.startOfDay(for: date)
        return activeSessionDays.contains(normalized)
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return calendar.isDateInToday(date)
    }

    private var activitySessions: [WorkoutSession] {
        historySessions
            .filter { $0.totalSets > 0 }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
    }

    private var lastDisplaySession: WorkoutSession? {
        activitySessions.first ?? historySessions.first
    }

    @ViewBuilder
    private var sessionDeckSection: some View {
        VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
            lastSessionPreview
        }
        .onAppear {
            #if DEBUG
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let monthDays = historySessions
                .filter { $0.totalSets > 0 && $0.endedAt != nil }
                .filter { session in
                    guard let ended = session.endedAt else { return false }
                    return calendar.isDate(ended, equalTo: currentMonthStart, toGranularity: .month)
                }
                .map { session -> String in
                    guard let ended = session.endedAt else { return "nil" }
                    return formatter.string(from: calendar.startOfDay(for: ended))
                }
            let today = calendar.startOfDay(for: Date())
            print("[HOME][DEBUG] today=\(formatter.string(from: today)) sessions total=\(historySessions.count) completedMonth=\(monthDays) todayActive=\(activeSessionDays.contains(today))")
            #endif
        }
    }

    @ViewBuilder
    private var lastSessionPreview: some View {
        if let last = lastDisplaySession {
            lastSessionCard(last)
        } else {
            noSessionsCard
        }
    }

    private func lastSessionCard(_ session: WorkoutSession) -> some View {
        Button {
            Haptics.playLightTap()
            isHistoryPresented = true
        } label: {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.routineTitle)
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text(dayLabel(for: session.endedAt ?? session.startedAt))
                        .appFont(.footnote, weight: .regular)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppStyle.glassContentPadding)
            }
        }
        .buttonStyle(.plain)
    }

    private var noSessionsCard: some View {
        Button {
            Haptics.playLightTap()
            isHistoryPresented = true
        } label: {
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No sessions yet")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(.secondary)
                    Text("Tap to view history")
                        .appFont(.footnote, weight: .regular)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppStyle.glassContentPadding)
            }
        }
        .buttonStyle(.plain)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private func handleDaySelection(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        selectedDayForHistory = day
        Haptics.playLightTap()
        #if DEBUG
        let count = sessionsOn(day: day).count
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        print("[HOME][DEBUG] tappedDay=\(formatter.string(from: day)) sessionsForDay=\(count)")
        #endif
        isDayHistoryPresented = true
    }

    private func dayLabel(for date: Date) -> String {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        if start == today { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), start == yesterday {
            return "Yesterday"
        }
        let day = calendar.component(.day, from: start)
        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM yyyy"
        let suffix: String
        let tens = day % 100
        if tens >= 11 && tens <= 13 {
            suffix = "th"
        } else {
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix) \(monthYearFormatter.string(from: start))"
    }

    private func onAtlasTap() {
        Haptics.playMediumTap()
    }

    private func sessionsOn(day: Date) -> [WorkoutSession] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return historySessions.filter { session in
            guard session.totalSets > 0, let ended = session.endedAt else { return false }
            return ended >= start && ended < end
        }
    }
}

struct DayCell: View {
    let date: Date?
    let calendar: Calendar
    let isToday: Bool
    let hasWorkout: Bool
    let hasSession: Bool
    let onSelect: ((Date) -> Void)?

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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let onSelect {
                            onSelect(date)
                        }
                    }
                if hasSession {
                    Capsule()
                        .fill(Color.primary.opacity(0.45))
                        .frame(width: 18, height: 2)
                }
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
