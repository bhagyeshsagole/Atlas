//
//  AllHistoryView.swift
//  Atlas
//
//  Overview: Minimal list of all SwiftData sessions (completed + in-progress).
//

import SwiftUI
import SwiftData

struct AllHistoryView: View {
    @Query(sort: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]) private var sessions: [WorkoutSession]
    @State private var expanded: Set<UUID> = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppStyle.cardContentSpacing) {
                Text("History")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                    .padding(.top, AppStyle.screenTopPadding)

                if sessions.isEmpty {
                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        Text("No history yet")
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppStyle.glassContentPadding)
                    }
                    .padding(.horizontal, AppStyle.screenHorizontalPadding)
                } else {
                    VStack(spacing: AppStyle.cardContentSpacing) {
                        ForEach(sessions, id: \.id) { session in
                            SessionRow(session: session, isExpanded: expanded.contains(session.id)) {
                                toggle(session.id)
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

    private func toggle(_ id: UUID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
        Haptics.playLightTap()
    }
}

private struct SessionRow: View {
    let session: WorkoutSession
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.routineTitle)
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(.primary)
                        Text(dateLine)
                            .appFont(.footnote, weight: .regular)
                            .foregroundStyle(.secondary)
                        Text(statsLine)
                            .appFont(.footnote, weight: .medium)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.footnote.weight(.semibold))
                }
                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }), id: \.id) { exercise in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .appFont(.footnote, weight: .semibold)
                                    .foregroundStyle(.primary)
                                ForEach(exercise.sets.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { set in
                                    Text(setLine(set))
                                        .appFont(.caption, weight: .regular)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppStyle.glassContentPadding)
        }
        .onTapGesture {
            onToggle()
        }
    }

    private var dateLine: String {
        if let ended = session.endedAt {
            return Self.dateFormatter.string(from: ended)
        } else {
            return "In progress — \(Self.dateFormatter.string(from: session.startedAt))"
        }
    }

    private var statsLine: String {
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
        return "Sets \(sets) • Reps \(reps) • Volume \(volumeString)"
    }

    private func setLine(_ set: SetLog) -> String {
        let tag = set.tagRaw
        let weight = set.weightKg.map { String(format: "%.1f kg", $0) } ?? "Body"
        return "\(tag) — \(weight) × \(set.reps)"
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d, yyyy · h:mm a"
        return df
    }()
}
