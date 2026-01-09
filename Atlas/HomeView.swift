//
//  HomeView.swift
//  Atlas
//
//  Home screen showing calendar, history underlines, friends tray, and Start Workout CTA.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var friendsStore: FriendsStore
    @Query(sort: [SortDescriptor(\Workout.date, order: .reverse)]) private var workouts: [Workout]
    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]) private var historySessions: [WorkoutSession]
    private let calendar = Calendar.current

    let startWorkout: () -> Void
    let openSettings: () -> Void

    @State private var showCalendarCard = false
    @State private var showStartButton = false
    @State private var isDayHistoryPresented = false
    @State private var selectedDayForHistory: Date = Date()
    @State private var showFriendsSheet = false

    private let friendsSpring: Animation = {
        .interactiveSpring(response: 0.35, dampingFraction: 0.8)
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    // Top bar
                    HStack {
                        Button { onAtlasTap() } label: {
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

                    Spacer(minLength: AppStyle.homeBottomSpacer)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding)
                .padding(.bottom, AppStyle.homeBottomInset)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 56) {
                FriendsPill(isVisible: showStartButton && showFriendsSheet == false) {
                    withAnimation(friendsSpring) {
                        showFriendsSheet = true
                    }
                }
                .offset(y: showFriendsSheet ? 400 : 0)
                .opacity(showFriendsSheet ? 0 : (showStartButton ? 1 : 0))
                .animation(friendsSpring, value: showFriendsSheet)
                .padding(.horizontal, 16)

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundGradient)
        .tint(.primary)
        .overlay(alignment: .bottom) {
            if showFriendsSheet {
                FriendsSheet(
                    store: friendsStore,
                    onDismiss: {
                        withAnimation(friendsSpring) {
                            showFriendsSheet = false
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .onAppear {
            withAnimation(AppMotion.primary) {
                showCalendarCard = true
            }
            withAnimation(AppMotion.primary.delay(0.05)) {
                showStartButton = true
            }
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
    HomeView(
        startWorkout: {},
        openSettings: {}
    )
    .modelContainer(for: Workout.self, inMemory: true)
}
