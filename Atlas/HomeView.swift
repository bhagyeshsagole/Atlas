//
//  HomeView.swift
//  Atlas
//
//  Home screen showing calendar and history underlines.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: [SortDescriptor(\Workout.date, order: .reverse)]) private var workouts: [Workout]
    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]) private var historySessions: [WorkoutSession]
    private let calendar = Calendar.current

    let startWorkout: () -> Void
    let openSettings: () -> Void

    @State private var showCalendarCard = false
    @State private var isDayHistoryPresented = false
    @State private var selectedDayForHistory: Date = Date()
    @State private var monthOffset: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Text("Atlas")
                    .font(.system(size: 34, weight: .bold))
                    .italic()
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    assert(Thread.isMainThread, "openSettings should run on main thread")
                    Haptics.playLightTap()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .tint(.primary)

            // Calendar card
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                    HStack {
                        Button {
                            withAnimation(AppMotion.primary) { shiftMonth(-1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        VStack(alignment: .center, spacing: 4) {
                            Text(currentMonthTitle)
                                .appFont(.title, weight: .semibold)
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Button {
                            withAnimation(AppMotion.primary) { shiftMonth(1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            .animation(AppMotion.primary, value: showCalendarCard)

            // Start button under calendar
            StartWorkoutPillButton {
                startWorkout()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .tint(.primary)
        .onAppear {
            withAnimation(AppMotion.primary) {
                showCalendarCard = true
            }
        }
        .navigationDestination(isPresented: $isDayHistoryPresented) {
            DayHistoryView(day: selectedDayForHistory)
        }
        .toolbar(.hidden, for: .navigationBar)
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
        let base = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: base)) ?? base
    }

    private func shiftMonth(_ delta: Int) {
        monthOffset += delta
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonthStart)?.count ?? 30
        let currentDay = calendar.component(.day, from: selectedDayForHistory)
        let clampedDay = min(max(1, currentDay), daysInMonth)
        if let adjusted = calendar.date(bySetting: .day, value: clampedDay, of: currentMonthStart) {
            selectedDayForHistory = adjusted
        }
        #if DEBUG
        print("[HOME][MONTH] offset=\(monthOffset) title=\(currentMonthTitle)")
        #endif
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity(0.92),
                Color.black.opacity(0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private func handleDaySelection(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        guard activeSessionDays.contains(day) else {
            Haptics.playLightTap()
            return
        }
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
    HomeView(startWorkout: {}, openSettings: {})
    .modelContainer(for: Workout.self, inMemory: true)
}
