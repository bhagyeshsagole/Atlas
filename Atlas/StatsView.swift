import SwiftUI
import SwiftData

struct StatsView: View {
    @StateObject private var statsStore = StatsStore()
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @State private var showCoverageDetail = false
    @State private var showCoachPlanConfirm = false
    @EnvironmentObject private var routineStore: RoutineStore

    private let spacing: CGFloat = 18

    var body: some View {
        let preferredUnit = WorkoutUnits(from: weightUnit)
        let metrics = statsStore.metrics(for: statsStore.selectedRange)
        let scores = metrics.muscle
        let coach = metrics.coach

        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    Text("Stats")
                        .appFont(.title, weight: .semibold)
                        .foregroundStyle(.white)

                    Picker("Range", selection: $statsStore.selectedRange) {
                        ForEach(StatsLens.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    MuscleCoverageCard(scores: scores, range: statsStore.selectedRange) {
                        Haptics.playLightTap()
                        showCoverageDetail = true
                    }

                    HStack(spacing: 14) {
                        WorkloadCard(metrics: metrics, range: statsStore.selectedRange, preferredUnit: preferredUnit)
                            .frame(maxWidth: .infinity, minHeight: 120)
                        CoachCard(coach: coach)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    CreateCoachPlanCard {
                        Haptics.playLightTap()
                        showCoachPlanConfirm = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.top)
        }
        .atlasBackground()
        .atlasBackgroundTheme(.stats)
        .sheet(isPresented: $showCoverageDetail) {
            MuscleCoverageDetailSheet(scores: scores, lens: statsStore.selectedRange)
        }
        .tint(.primary)
        .animation(.easeInOut(duration: 0.28), value: statsStore.selectedRange)
        .onAppear {
            statsStore.updateSessions(Array(allSessions))
        }
        .onChange(of: allSessions) { _, newValue in
            statsStore.updateSessions(Array(newValue))
        }
        .alert("Create 10/10 Routine?", isPresented: $showCoachPlanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Create", role: .none) {
                createCoachPlans(from: metrics)
            }
        } message: {
            Text("This will add coach-generated routines to Start Workout for \(statsStore.selectedRange.rawValue). They’ll disappear after you complete them.")
        }
    }

    private func createCoachPlans(from metrics: StatsMetrics) {
        let plans = CoachPlanGenerator.generatePlans(for: metrics, range: statsStore.selectedRange)
        for routine in plans {
            routineStore.addRoutine(routine)
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
        guard let bucketScore = scores[bucket] else {
            return AnyView(EmptyView())
        }
        let displayValue: String = (range == .all) ? "\(Int(bucketScore.progress01 * 100))%" : "\(bucketScore.score0to10) / 10"
        let view = VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bucket.displayName)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(displayValue)
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
                        .frame(width: max(8, geo.size.width * CGFloat(min(bucketScore.progress01, 1.0))))
                        .animation(.easeOut(duration: 0.25), value: bucketScore.progress01)
                }
            }
            .frame(height: 10)
        }
        return AnyView(view)
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
    @State private var activeChatContext: MuscleCoachContext?

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
                                    detailRow(score: score) {
                                        activeChatContext = MuscleCoachContext(
                                            selectedRange: lens,
                                            bucket: bucket,
                                            score: score.score0to10,
                                            reasons: score.reasons,
                                            suggestions: score.suggestions
                                        )
                                    }
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
        .sheet(item: $activeChatContext) { context in
            CoachChatView(context: context)
                .presentationDetents([.medium, .large])
        }
    }

    private func detailRow(score: BucketScore, onTap: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(score.bucket.displayName)
                    .appFont(.body, weight: .semibold)
                Spacer()
                if lens == .all {
                    Text("\(Int(score.progress01 * 100))%")
                        .appFont(.body, weight: .semibold)
                } else {
                    Text("\(score.score0to10) / 10")
                        .appFont(.body, weight: .semibold)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }

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

private enum CoachPlanGenerator {
    static func generatePlans(for metrics: StatsMetrics, range: StatsLens) -> [Routine] {
        let planId = UUID()
        let sortedBuckets = metrics.muscle.values.sorted { $0.score0to10 < $1.score0to10 }
        let targetBuckets = Array(sortedBuckets.prefix(max(1, min(3, sortedBuckets.count))))

        var routines: [Routine] = []
        for bucketScore in targetBuckets {
            let exercises = exercises(for: bucketScore.bucket)
            guard exercises.isEmpty == false else { continue }
            let workouts = exercises.map { name in
                RoutineWorkout(id: UUID(), name: name, wtsText: "3x8", repsText: "3x8")
            }
            let routine = Routine(
                id: UUID(),
                name: bucketScore.bucket.displayName,
                createdAt: Date(),
                workouts: workouts,
                summary: "Coach-generated to shore up \(bucketScore.bucket.displayName) and reach 10/10.",
                source: .coach,
                coachPlanId: planId,
                expiresOnCompletion: true,
                generatedForRange: range,
                coachName: "Titan",
                coachGroup: "Coach Group \(planId.uuidString.prefix(4))"
            )
            routines.append(routine)
        }

        if routines.isEmpty {
            let fallbackExercises = ["Squat", "Row", "Press", "Core Plank"]
            let workouts = fallbackExercises.map { name in
                RoutineWorkout(id: UUID(), name: name, wtsText: "3x8", repsText: "3x8")
            }
            let fallback = Routine(
                id: UUID(),
                name: "Balanced",
                createdAt: Date(),
                workouts: workouts,
                summary: "Coach-generated to balance your week and reach 10/10.",
                source: .coach,
                coachPlanId: planId,
                expiresOnCompletion: true,
                generatedForRange: range,
                coachName: "Titan",
                coachGroup: "Coach Group \(planId.uuidString.prefix(4))"
            )
            routines.append(fallback)
        }

        return routines
    }

    private static func exercises(for bucket: MuscleGroup) -> [String] {
        switch bucket {
        case .legs:
            return ["Back Squat", "Romanian Deadlift", "Walking Lunge", "Calf Raise"]
        case .back:
            return ["Pull-Up or Lat Pulldown", "Barbell Row", "Single-Arm Dumbbell Row", "Face Pull"]
        case .chest:
            return ["Bench Press", "Incline Dumbbell Press", "Push-Up", "Cable Fly"]
        case .shoulders:
            return ["Overhead Press", "Dumbbell Lateral Raise", "Rear Delt Fly", "Face Pull"]
        case .arms:
            return ["Barbell Curl", "Hammer Curl", "Tricep Pressdown", "Dips"]
        case .core:
            return ["Plank", "Hanging Knee Raise", "Pallof Press", "Farmer Carry"]
        }
    }
}

private struct CreateCoachPlanCard: View {
    let onTap: () -> Void

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Create 10/10 Routine")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                Text("Generate coach routines to cover weak spots. They disappear after you complete them.")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                AtlasPillButton("Create") {
                    onTap()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
