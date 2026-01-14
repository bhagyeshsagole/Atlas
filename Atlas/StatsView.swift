import SwiftUI
import SwiftData

struct StatsView: View {
    @StateObject private var store = StatsDashboardStore()
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]
    @EnvironmentObject var healthKitStore: HealthKitStore
    @AppStorage("weightUnit") private var weightUnit: String = "lb"
    @AppStorage("statsShowMinimums") private var statsShowMinimums = true
    @AppStorage("statsShowMuscles") private var statsShowMuscles = true
    @AppStorage("statsShowSections") private var statsShowSections = true
    @AppStorage("statsShowAlerts") private var statsShowAlerts = true
    @State private var activeDetail: MetricDetailModel?
    @State private var activeMuscle: MuscleOverviewModel?
    @State private var showManagePins = false
    @State private var showCoachSheet = false
    @State private var cardioWorkouts: [HealthWorkoutSummary] = []
    @State private var isLoadingCardio = false

    private var preferredUnit: WorkoutUnits { WorkoutUnits(from: weightUnit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                topControls
                cardsRow
                if store.mode == .athletic && !cardioWorkouts.isEmpty {
                    cardioSection
                }
                if statsShowMinimums {
                    minimumStrip
                }
                if statsShowMuscles {
                    musclesOverview
                }
                if statsShowSections {
                    sections
                }
                if statsShowAlerts {
                    alertsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .atlasBackground()
        .atlasBackgroundTheme(.stats)
        .sheet(item: $activeDetail) { detail in
            MetricDetailView(detail: detail, unit: preferredUnit)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $activeMuscle) { muscle in
            MuscleDetailView(muscle: muscle)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showManagePins) {
            KeyLiftManagerView(
                pinned: Binding(
                    get: { store.pinnedLifts },
                    set: { store.pinnedLifts = $0 }
                ),
                availableExercises: store.availableExercises
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCoachSheet) {
            CoachQuickSheet(
                statsContext: coachContext,
                exerciseName: nil,
                balanceContext: balanceContextText
            )
        }
        .onAppear {
            store.updatePreferredUnit(preferredUnit)
            store.updateSessions(Array(allSessions))
            loadCardioWorkouts()
        }
        .onChange(of: allSessions) { _, newValue in
            store.updateSessions(Array(newValue))
        }
        .onChange(of: weightUnit) { _, newValue in
            store.updatePreferredUnit(WorkoutUnits(from: newValue))
        }
        .onChange(of: store.mode) { _, _ in
            loadCardioWorkouts()
        }
        .onChange(of: store.range) { _, _ in
            loadCardioWorkouts()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stats")
                    .appFont(.title, weight: .semibold)
                    .foregroundStyle(.white)
                Text(store.mode.title)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CoachButton {
                Haptics.playLightTap()
                showCoachSheet = true
            }
        }
    }

    private var topControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $store.mode) {
                ForEach(StatsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StatsRange.allCases) { range in
                        ChipButton(title: range.title, isSelected: store.range == range) {
                            Haptics.playLightTap()
                            store.range = range
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                ForEach(StatsExerciseFilter.allCases) { filter in
                    ChipButton(title: filter.title, isSelected: store.filter == filter) {
                        Haptics.playLightTap()
                        store.filter = filter
                        if filter == .keyLifts && store.pinnedLifts.isEmpty {
                            showManagePins = true
                        }
                    }
                }
                Spacer()
                Button {
                    Haptics.playLightTap()
                    showManagePins = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    private var coachContext: String {
        let mode = store.mode.title
        let range = store.range.title
        let filter = store.filter.title
        let highlights = store.dashboard.cards.map { "\($0.title): \($0.primaryValue)" }.joined(separator: "; ")
        return "Mode: \(mode). Range: \(range). Filter: \(filter). Highlights: \(highlights)"
    }

    private var balanceContextText: String? {
        if let balanceCard = store.dashboard.cards.first(where: { $0.metric == .balance }) {
            return "Balance status: \(balanceCard.primaryValue). \(balanceCard.comparisonText)"
        }
        return nil
    }

    private var cardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(store.dashboard.cards) { card in
                    TrendCardView(card: card)
                        .frame(width: 220)
                        .onTapGesture {
                            Haptics.playLightTap()
                            if let detail = store.dashboard.detail[card.metric] {
                                activeDetail = detail
                            }
                        }
                }
                if store.dashboard.cards.isEmpty {
                    GlassSkeleton(height: 140, width: 220)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var minimumStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimums")
                .appFont(.section, weight: .bold)
                .foregroundStyle(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.dashboard.minimumStrip) { metric in
                        MinimumStripView(metric: metric, dataPointCount: metric.weekly.count)
                    }
                }
            }
        }
    }

    private var musclesOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscles")
                .appFont(.section, weight: .bold)
                .foregroundStyle(.primary)
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    if store.dashboard.muscles.isEmpty {
                        GlassSkeleton(height: 80, width: UIScreen.main.bounds.width * 0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(store.dashboard.muscles) { muscle in
                            MuscleRow(muscle: muscle)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Haptics.playLightTap()
                                    activeMuscle = muscle
                                }
                            if muscle.id != store.dashboard.muscles.last?.id {
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
                .padding(AppStyle.glassContentPadding)
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(store.dashboard.sections.prefix(4)) { section in
                SectionCard(section: section) {
                    if let detail = store.dashboard.detail[section.metric] {
                        activeDetail = detail
                    }
                }
            }
        }
    }

    private var alertsSection: some View {
        Group {
            if !store.dashboard.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerts")
                        .appFont(.section, weight: .bold)
                        .foregroundStyle(.primary)
                    ForEach(store.dashboard.alerts) { alert in
                        Text("• \(alert.message)")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var cardioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cardio")
                .appFont(.section, weight: .bold)
                .foregroundStyle(.primary)
            GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(cardioWorkouts.prefix(5)) { workout in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.activityType)
                                    .appFont(.body, weight: .semibold)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let distance = workout.distanceKm {
                                        Text(String(format: "%.1f km", distance))
                                            .appFont(.caption, weight: .semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(workout.durationMinutes) min")
                                        .appFont(.caption, weight: .semibold)
                                        .foregroundStyle(.secondary)
                                    if let calories = workout.activeEnergyKcal {
                                        Text("\(Int(calories)) cal")
                                            .appFont(.caption, weight: .semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Text(workout.startDate, style: .date)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                        if workout.id != cardioWorkouts.prefix(5).last?.id {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
                .padding(AppStyle.glassContentPadding)
            }
        }
    }

    private func loadCardioWorkouts() {
        guard healthKitStore.isAuthorized else { return }
        guard store.mode == .athletic else {
            cardioWorkouts = []
            return
        }

        isLoadingCardio = true
        Task {
            let interval = store.range.dateInterval()
            do {
                let workouts = try await healthKitStore.fetchWorkoutsWithCache(
                    from: interval.start,
                    to: interval.end
                )
                await MainActor.run {
                    cardioWorkouts = workouts
                    isLoadingCardio = false
                }
            } catch {
                await MainActor.run {
                    cardioWorkouts = []
                    isLoadingCardio = false
                }
                #if DEBUG
                print("[Stats] Failed to load cardio: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Subviews

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.footnote, weight: .semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct CoachButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Coach")
                    .appFont(.footnote, weight: .semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MuscleRow: View {
    let muscle: MuscleOverviewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.muscle.displayName)
                    .appFont(.body, weight: .semibold)
                Text("\(muscle.latestSets) sets / wk")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if muscle.weekly.isEmpty == false {
                MiniLineChart(series: muscle.weekly, baseline: nil)
                    .frame(width: 90, height: 48)
            }
        }
    }
}

private struct TrendCardView: View {
    let card: TrendCardModel

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(card.primaryValue)
                            .appFont(.title3, weight: .bold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: arrowName(card.direction))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(card.direction == .down ? Color.red.opacity(0.8) : Color.green.opacity(0.9))
                }
                Text(card.comparisonText)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(card.streakText)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                if let context = card.context {
                    Text(context)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func arrowName(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }
}

private struct MinimumStripView: View {
    let metric: MinimumStripMetric
    let dataPointCount: Int

    private var calculatedWidth: CGFloat {
        // Calculate width based on data points to ensure bars are readable
        // Minimum 140 for small ranges, scale up for larger ranges
        let baseWidth: CGFloat = 140
        let additionalWidthPerPoint: CGFloat = 8
        let extraWidth = CGFloat(max(0, dataPointCount - 7)) * additionalWidthPerPoint
        return baseWidth + extraWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            MiniBarChart(series: metric.weekly, baseline: metric.baseline?.floor ?? 0)
                .frame(height: 46)
            if let baseline = metric.baseline {
                Text(baseline.statusText)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: calculatedWidth)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MiniBarChart: View {
    let series: [WeeklyMetricValue]
    let baseline: Double

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(series.map(\.value).max() ?? 1, baseline > 0 ? baseline : 1)
            // Adaptive spacing: use smaller spacing for longer ranges
            let spacing: CGFloat = series.count > 12 ? 2 : 4
            let barWidth = max(4, (geo.size.width - spacing * CGFloat(max(series.count - 1, 0))) / CGFloat(max(series.count, 1)))
            ZStack(alignment: .bottomLeading) {
                if baseline > 0 {
                    let y = geo.size.height * CGFloat(1 - baseline / maxValue)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                }
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(series) { point in
                        let height = max(4, CGFloat(point.value / maxValue) * geo.size.height)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.32))
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SectionCard: View {
    let section: StatsSectionModel
    var onTap: () -> Void

    var body: some View {
        GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .appFont(.body, weight: .semibold)
                        if let description = section.description {
                            Text(description)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if !section.series.isEmpty {
                    MiniLineChart(series: section.series, baseline: section.baseline)
                        .frame(height: 120)
                }

                if let baseline = section.baseline {
                    Text(baseline.statusText)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }

                if !section.breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(section.breakdown) { item in
                            HStack {
                                Text(item.title)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(item.valueText)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary)
                            }
                            if let detail = item.detail {
                                Text(detail)
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
    }
}

private struct MiniLineChart: View {
    let series: [WeeklyMetricValue]
    let baseline: BaselineResult?

    var body: some View {
        GeometryReader { geo in
            let values = series.map(\.value)
            let maxValue = max(values.max() ?? 1, baseline?.band?.upperBound ?? 0, baseline?.floor ?? 0, 1)
            let minValue = 0.0
            let points: [CGPoint] = series.enumerated().map { index, point in
                let x = geo.size.width * CGFloat(Double(index) / Double(max(series.count - 1, 1)))
                let normalized = (point.value - minValue) / max(maxValue - minValue, 0.0001)
                let y = geo.size.height * CGFloat(1 - normalized)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if let band = baseline?.band {
                    let lowerValue = min(band.lowerBound, band.upperBound)
                    let upperValue = max(band.lowerBound, band.upperBound)
                    let lowerY = geo.size.height * CGFloat(1 - lowerValue / maxValue)
                    let upperY = geo.size.height * CGFloat(1 - upperValue / maxValue)
                    let height = max(2, lowerY - upperY)
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: height)
                        .offset(y: upperY)
                }

                if let baseline = baseline {
                    let y = geo.size.height * CGFloat(1 - (baseline.floor / maxValue))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if points.count >= 2 {
                    Path { path in
                        path.move(to: points.first!)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(Color.white.opacity(0.8), lineWidth: 2)
                } else if let point = points.first {
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
    }
}

private struct GlassSkeleton: View {
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.glassCardCornerRadiusLarge)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shimmering()
    }
}

private struct MuscleDetailView: View {
    let muscle: MuscleOverviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(muscle.muscle.displayName)
                .appFont(.title3, weight: .semibold)
            if !muscle.weekly.isEmpty {
                MiniLineChart(series: muscle.weekly, baseline: BaselineResult(floor: muscle.floor, band: muscle.band, type: .default, streakWeeks: 0, deltaPercent: 0))
                    .frame(height: 160)
            }
            Text("Top exercises")
                .appFont(.section, weight: .bold)
            if muscle.topExercises.isEmpty {
                Text("Log a few sets to see contributors.")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(muscle.topExercises) { item in
                        HStack {
                            Text(item.title)
                                .appFont(.body, weight: .semibold)
                            Spacer()
                            Text(item.valueText)
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(AppStyle.contentPaddingLarge)
        .atlasBackground()
        .atlasBackgroundTheme(.stats)
    }
}

// MARK: - Metric Detail

struct MetricDetailView: View {
    let detail: MetricDetailModel
    let unit: WorkoutUnits

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .appFont(.title3, weight: .semibold)
                    Text(detail.contextLines.first ?? "")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !detail.series.isEmpty {
                MiniLineChart(series: detail.series, baseline: detail.baseline)
                    .frame(height: 180)
            }

            if let baseline = detail.baseline {
                Text(baseline.statusText)
                    .appFont(.body, weight: .semibold)
            }

            if detail.contextLines.count > 1 {
                ForEach(detail.contextLines.dropFirst(), id: \.self) { line in
                    Text(line)
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }

            if !detail.breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detail.breakdown) { item in
                        HStack {
                            Text(item.title)
                                .appFont(.body, weight: .semibold)
                            Spacer()
                            Text(item.valueText)
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                        if let detail = item.detail {
                            Text(detail)
                                .appFont(.footnote, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !detail.learnMore.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learn more")
                        .appFont(.section, weight: .bold)
                    ForEach(detail.learnMore, id: \.self) { line in
                        Text(line)
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(AppStyle.contentPaddingLarge)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
    }
}

// MARK: - Key lifts manager

private struct KeyLiftManagerView: View {
    @Binding var pinned: [String]
    let availableExercises: [String]
    @Environment(\.dismiss) private var dismiss

    private var categorizedExercises: [MuscleGroup: [String]] {
        ExerciseClassifier.categorize(exercises: availableExercises)
    }

    private var sortedCategories: [MuscleGroup] {
        MuscleGroup.allCases.filter { categorizedExercises[$0]?.isEmpty == false }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Manage Key Lifts")
                    .appFont(.title3, weight: .semibold)
                    .padding(.bottom, 4)

                if sortedCategories.isEmpty {
                    Text("No exercises yet. Complete some workouts to track progress.")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(sortedCategories) { category in
                                NavigationLink {
                                    CategoryExercisesView(
                                        category: category,
                                        exercises: categorizedExercises[category] ?? [],
                                        pinned: $pinned
                                    )
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(category.rawValue)
                                                .appFont(.body, weight: .semibold)
                                                .foregroundStyle(.primary)

                                            Text("\(categorizedExercises[category]?.count ?? 0) exercises")
                                                .appFont(.caption, weight: .medium)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CategoryExercisesView: View {
    let category: MuscleGroup
    let exercises: [String]
    @Binding var pinned: [String]
    @State private var searchText: String = ""

    private var filtered: [String] {
        guard searchText.isEmpty == false else { return exercises.sorted() }
        return exercises.filter { $0.localizedCaseInsensitiveContains(searchText) }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search \(category.rawValue.lowercased())", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, 8)

            if filtered.isEmpty {
                Text("No matching exercises.")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppStyle.contentPaddingLarge)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { (name: String) in
                            HStack {
                                Text(name)
                                    .appFont(.body, weight: .medium)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if pinned.contains(normalize(name)) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 12)
                            .padding(.horizontal, AppStyle.contentPaddingLarge)
                            .onTapGesture {
                                Haptics.playLightTap()
                                toggle(name)
                            }

                            if name != filtered.last {
                                Divider()
                                    .padding(.leading, AppStyle.contentPaddingLarge)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ name: String) {
        let normalized = normalize(name)
        if pinned.contains(normalized) {
            pinned.removeAll { $0 == normalized }
        } else {
            pinned.append(normalized)
        }
    }

    private func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct CoachQuickSheet: View {
    enum Preset: String, CaseIterable, Identifiable {
        case explainStats
        case nextWorkout
        case formCues
        case fixBalance

        var id: String { rawValue }
        var title: String {
            switch self {
            case .explainStats: return "Explain my stats this week"
            case .nextWorkout: return "What should I do next workout?"
            case .formCues: return "Form cues for this exercise"
            case .fixBalance: return "Fix my balance (push/pull, quad/hinge)"
            }
        }
    }

    let statsContext: String?
    let exerciseName: String?
    let balanceContext: String?

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var response: String = ""
    @State private var errorMessage: String?
    @State private var customPrompt: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Coach")
                    .appFont(.title3, weight: .semibold)
                Text("Quick prompts")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Preset.allCases) { preset in
                        Button {
                            ask(preset)
                        } label: {
                            HStack {
                                Text(preset.title)
                                    .appFont(.body, weight: .semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isLoading, response.isEmpty {
                                    ProgressView()
                                        .tint(.primary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                Text("Or ask anything")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Type your question...", text: $customPrompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .focused($isTextFieldFocused)
                        .disabled(isLoading)
                        .onSubmit {
                            sendCustomPrompt()
                        }

                    Button {
                        sendCustomPrompt()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(.red)
                }

                if !response.isEmpty {
                    GlassCard {
                        Text(response)
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppStyle.glassContentPadding)
                    }
                }

                Spacer()
            }
            .padding(AppStyle.contentPaddingLarge)
            .atlasBackground()
            .atlasBackgroundTheme(.stats)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ask(_ preset: Preset) {
        isLoading = true
        response = ""
        errorMessage = nil
        Task {
            let promptText = buildPrompt(for: preset)
            if OpenAIConfig.isAIAvailable == false {
                await MainActor.run {
                    response = fallback(for: preset)
                    isLoading = false
                }
                return
            }
            do {
                let reply = try await OpenAIChatClient.chat(prompt: promptText)
                await MainActor.run {
                    response = reply
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Coach unavailable. Try again after logging."
                    response = fallback(for: preset)
                }
            }
        }
    }

    private func sendCustomPrompt() {
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        response = ""
        errorMessage = nil
        isTextFieldFocused = false

        Task {
            let promptText = buildCustomPrompt(trimmed)
            if OpenAIConfig.isAIAvailable == false {
                await MainActor.run {
                    response = "Coach unavailable offline. Try: explain my stats, recommend next workout, or form tips."
                    isLoading = false
                    customPrompt = ""
                }
                return
            }
            do {
                let reply = try await OpenAIChatClient.chat(prompt: promptText)
                await MainActor.run {
                    response = reply
                    isLoading = false
                    customPrompt = ""
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Coach unavailable. Try again after logging."
                    response = "Connection error. Check your internet and auth status."
                    customPrompt = ""
                }
            }
        }
    }

    private func buildPrompt(for preset: Preset) -> String {
        var context: [String] = []
        if let statsContext { context.append("Stats: \(statsContext)") }
        if let exerciseName { context.append("Exercise: \(exerciseName)") }
        if let balanceContext { context.append("Balance: \(balanceContext)") }
        let contextBlock = context.joined(separator: "\n")
        let ask: String
        switch preset {
        case .explainStats:
            ask = "Explain my training this week in simple terms and what to focus on next."
        case .nextWorkout:
            ask = "Recommend what to do next workout with sets/reps."
        case .formCues:
            let name = exerciseName ?? "my main lift"
            ask = "Give concise form cues for \(name)."
        case .fixBalance:
            ask = "Help me fix push/pull and quad/hinge balance."
        }

        return """
System:
You are Titan, a concise lifting coach. Reply in 3–5 short lines. Be specific with sets/reps and keep tone calm.

Context:
\(contextBlock)

User:
\(ask)
"""
    }

    private func buildCustomPrompt(_ userQuestion: String) -> String {
        var context: [String] = []
        if let statsContext { context.append("Stats: \(statsContext)") }
        if let exerciseName { context.append("Exercise: \(exerciseName)") }
        if let balanceContext { context.append("Balance: \(balanceContext)") }
        let contextBlock = context.joined(separator: "\n")

        return """
System:
You are Titan, a concise lifting coach. Reply in 3–5 short lines. Be specific with sets/reps and keep tone calm.

Context:
\(contextBlock)

User:
\(userQuestion)
"""
    }

    private func fallback(for preset: Preset) -> String {
        switch preset {
        case .explainStats:
            return "Focus on showing up 3x this week and repeating your heaviest sets. Add 1–2 reps if the last week felt easy."
        case .nextWorkout:
            return "Next workout: pick 3 big lifts (3–4×6–10) and 2 accessories (2–3×10–15). Keep rest ~2 min and log your top set."
        case .formCues:
            return "Brace hard, full feet on the floor, control the descent, drive evenly on the way up. Film a set to check depth and bar path."
        case .fixBalance:
            return "Add a pull for every push and a hinge for every quad lift this week. If short on time, swap one push for a row and one quad for an RDL."
        }
    }
}

private extension View {
    func shimmering() -> some View {
        self
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.25), Color.white.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: -150)
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: UUID())
            )
    }
}
