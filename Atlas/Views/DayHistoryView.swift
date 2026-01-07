//
//  DayHistoryView.swift
//  Atlas
//
//  What this file is:
//  - Shows all sessions completed on a specific day with basic stats.
//
//  Where it’s used:
//  - Navigated from the Home calendar when tapping a marked day.
//
//  Called from:
//  - `HomeView` navigationDestination presents this when a day cell is tapped.
//
//  Key concepts:
//  - Filters a live `@Query` of all sessions down to those ending within the tapped day.
//
//  Safe to change:
//  - Visual styling, wording, or which stats display.
//
//  NOT safe to change:
//  - The date filter window (start to start+1 day); altering it can include the wrong sessions.
//
//  Common bugs / gotchas:
//  - Sessions with `totalSets == 0` are intentionally hidden to avoid draft clutter.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Session History v1 — Pass 2
//

import SwiftUI
import SwiftData

struct DayHistoryView: View {
    let day: Date
    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]) private var allSessions: [WorkoutSession] // Live feed of all sessions; filtered per day below.

    private var sessionsForDay: [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allSessions.filter { session in
            guard session.totalSets > 0, let ended = session.endedAt else { return false }
            return ended >= start && ended < end
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                Text(titleString)
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                    .padding(.top, AppStyle.screenTopPadding)

                if sessionsForDay.isEmpty {
                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        Text("No sessions for this day")
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppStyle.glassContentPadding)
                    }
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                } else {
                    VStack(spacing: AppStyle.cardContentSpacing) {
                        ForEach(sessionsForDay, id: \.id) { session in
                            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(session.routineTitle)
                                        .appFont(.title3, weight: .semibold)
                                        .foregroundStyle(.primary)
                                    Text(timeLine(for: session))
                                        .appFont(.footnote, weight: .regular)
                                        .foregroundStyle(.secondary)
                                    Text(statsLine(for: session))
                                        .appFont(.footnote, weight: .medium)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppStyle.glassContentPadding)
                            }
                        }
                    }
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                    .padding(.bottom, AppStyle.screenTopPadding)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: Calendar.current.startOfDay(for: day))
    }

    private func statsLine(for session: WorkoutSession) -> String {
        let sets = session.totalSets
        let reps = session.totalReps
        let volumeKg = session.volumeKg
        let volumeLb = volumeKg * WorkoutSessionFormatter.kgToLb
        let volumeString: String
        if volumeKg > 0 {
            volumeString = String(format: "%.0f kg / %.0f lb", volumeKg, volumeLb)
        } else {
            volumeString = "—"
        }
        return "Sets \(sets) · Reps \(reps) · Volume \(volumeString)"
    }

    private func timeLine(for session: WorkoutSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let ended = session.endedAt {
            return formatter.string(from: ended)
        }
        return formatter.string(from: session.startedAt)
    }
}
