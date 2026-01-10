import SwiftUI
import SwiftData

struct StatsView: View {
    @StateObject private var statsStore = StatsStore()
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @State private var selectedLens: StatsLens = .week
    @State private var showCoverageDetail = false

    private let spacing: CGFloat = 18

    var body: some View {
        let preferredUnit = WorkoutUnits(from: weightUnit)
        let metrics = statsStore.metrics(for: selectedLens)
        let scores = metrics.muscle
        let coach = metrics.coach

        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: spacing) {
                Text("Stats")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.white)

                Picker("Range", selection: $selectedLens) {
                    ForEach(StatsLens.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                MuscleCoverageCard(scores: scores, range: selectedLens) {
                    Haptics.playLightTap()
                    showCoverageDetail = true
                }

                HStack(spacing: 14) {
                    WorkloadCard(metrics: metrics, range: selectedLens, preferredUnit: preferredUnit)
                        .frame(maxWidth: .infinity, minHeight: 120)
                    CoachCard(coach: coach)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
            .padding(.bottom, 110)
        }
        .sheet(isPresented: $showCoverageDetail) {
            MuscleCoverageDetailSheet(scores: scores, lens: selectedLens)
        }
        .tint(.primary)
        .animation(.easeInOut(duration: 0.28), value: selectedLens)
        .onAppear {
            statsStore.updateSessions(Array(allSessions))
        }
        .onChange(of: allSessions) { _, newValue in
            statsStore.updateSessions(Array(newValue))
        }
    }

}

private struct WorkloadCard: View {
    let metrics: StatsMetrics
    let range: StatsLens
    let preferredUnit: WorkoutUnits

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workload")
                    .appFont(.section, weight: .bold)
                    .foregroundStyle(.primary)

                statRow(label: "Volume", value: volumeDisplay)
                statRow(label: "Sets", value: formatNumber(Double(metrics.workload.sets)))
                statRow(label: "Reps", value: formatNumber(Double(metrics.workload.reps)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var volumeDisplay: String {
        let value = preferredUnit == .kg ? metrics.workload.volume : metrics.workload.volume * WorkoutSessionFormatter.kgToLb
        let formatted = String(format: "%.0f", value)
        let unitText = preferredUnit == .kg ? "kg" : "lb"
        return "\(formatted) \(unitText)"
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .appFont(.body, weight: .regular)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

}

private struct MuscleCoverageCard: View {
    let scores: [MuscleGroup: BucketScore]
    let range: StatsLens
    var onTap: () -> Void

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Muscle Coverage")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                }

                if scores.isEmpty {
                    Text("No sessions yet.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(MuscleBucket.allCases) { bucket in
                            muscleRow(for: bucket)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func muscleRow(for bucket: MuscleBucket) -> some View {
        let score = scores[bucket]?.score ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bucket.displayName)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("\(score.score0to10) / 10")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.28))
                        .frame(width: max(8, geo.size.width * CGFloat(min(score.progress0to1, 1.0))))
                        .animation(.easeOut(duration: 0.25), value: score)
                }
            }
            .frame(height: 10)
        }
    }
}

private struct CoachCard: View {
    let coach: CoachSummary

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coach")
                    .appFont(.section, weight: .bold)
                    .foregroundStyle(.primary)

                statRow(label: "Streak", value: "\(coach.streakWeeks) wks")
                statRow(label: "Next", value: coach.next)
                Text(coach.reason)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.primary.opacity(0.6))
                    .padding(.top, 4)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .appFont(.body, weight: .regular)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
        }
    }
}

private struct MuscleCoverageDetailSheet: View {
    let scores: [MuscleGroup: BucketScore]?
    let lens: StatsLens

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Muscle Coverage")
                            .appFont(.title3, weight: .semibold)
                        Text(lens.rawValue)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let scores, !scores.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(MuscleBucket.allCases) { bucket in
                                if let score = scores[bucket] {
                                    detailRow(score: score)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.primary)
                        Text("Preparing coverage details...")
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(AppStyle.contentPaddingLarge)
            .background(Color.black.opacity(0.95).ignoresSafeArea())
        }
    }

private func detailRow(score: BucketScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(score.bucket.displayName)
                    .appFont(.body, weight: .semibold)
                Spacer()
                Text("\(score.score0to10) / 10")
                    .appFont(.body, weight: .semibold)
            }
            .foregroundStyle(.primary)

            if !score.reasons.isEmpty {
                Text("Why")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                ForEach(score.reasons, id: \.self) { reason in
                    Text("• \(reason)")
                        .appFont(.footnote, weight: .regular)
                        .foregroundStyle(.primary)
                }
            }

            if !score.suggestions.isEmpty {
                Text("To reach 10/10")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                ForEach(score.suggestions, id: \.self) { suggestion in
                    Text("• \(suggestion)")
                        .appFont(.footnote, weight: .regular)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
