import Foundation

struct SessionData: Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let isHidden: Bool
    let totalSets: Int
    let durationSeconds: Int?
    let exercises: [ExerciseData]
}

struct ExerciseData: Sendable {
    let name: String
    let orderIndex: Int
    let sets: [SetData]
}

struct SetData: Sendable {
    let tagRaw: String
    let weightKg: Double?
    let reps: Int
    let createdAt: Date
}

struct StatsMetricEngine {
    struct JunkSummary {
        var totalJunkSets: Int
        var byExercise: [String: Int]
    }

    struct ProcessedData {
        let weeks: [Date]
        let rangeWeeks: [Date]
        let weeklyTonnage: [Date: Double]
        let weeklyHardSets: [Date: Int]
        let weeklyHardSetsByMuscle: [Date: [MuscleGroup: Int]]
        let hardSetContributors: [MuscleGroup: [String: Int]]
        let weeklyOverloadEvents: [Date: Int]
        let weeklyTopSetByExercise: [Date: [String: Double]]
        let weeklyLaRTByExercise: [Date: [String: Double]]
        let weeklyMedianRest: [Date: Double]
        let weeklyPushPull: [Date: (push: Int, pull: Int)]
        let weeklyQuadHinge: [Date: (quad: Int, hinge: Int)]
        let weeklyRepExposure: [Date: [RepBucket: Int]]
        let weeklyDensity: [Date: Double]
        let weeklyHardSetDensity: [Date: Double]
        let weeklyCoverageTouches: [Date: [MuscleGroup: Set<Date>]]
        let exerciseVarietyByMuscle: [MuscleGroup: Set<String>]
        let junk: JunkSummary
    }

    enum RepBucket: String, CaseIterable, Hashable {
        case oneToSix
        case fiveToEight
        case nineToFifteen
        case sixteenToThirty
    }

    enum JunkBucket: String, CaseIterable, Hashable {
        case fiveToEight
        case nineToFifteen
        case sixteenToThirty

        static func from(reps: Int) -> JunkBucket? {
            switch reps {
            case 5...8: return .fiveToEight
            case 9...15: return .nineToFifteen
            case 16...30: return .sixteenToThirty
            default: return nil
            }
        }
    }

    private struct JunkCandidate {
        let exerciseId: String
        let exerciseName: String
        let week: Date
        let weight: Double
        let bucket: JunkBucket
        let inRange: Bool
    }

    private struct SessionAccumulator {
        var tonnage: Double = 0
        var hardSets: Int = 0
        var firstSetAt: Date?
        var lastSetAt: Date?
        var durationSeconds: Int?
        var endedAt: Date
    }

    static func computeDashboard(
        sessions: [SessionData],
        pinnedLifts: [String],
        mode: StatsMode,
        range: StatsRange,
        filter: StatsExerciseFilter,
        preferredUnit: WorkoutUnits,
        now: Date = Date(),
        calendar: Calendar = DateRanges.isoCalendar()
    ) -> StatsDashboardResult {
        let processed = processSessions(
            sessions: sessions,
            range: range,
            now: now,
            calendar: calendar
        )

        switch mode {
        case .strength:
            return buildStrengthDashboard(processed: processed, pinnedLifts: pinnedLifts, filter: filter, preferredUnit: preferredUnit, range: range, calendar: calendar)
        case .hypertrophy:
            return buildHypertrophyDashboard(processed: processed, pinnedLifts: pinnedLifts, filter: filter, preferredUnit: preferredUnit, range: range, calendar: calendar)
        case .athletic:
            return buildAthleticDashboard(processed: processed, pinnedLifts: pinnedLifts, filter: filter, preferredUnit: preferredUnit, range: range, calendar: calendar)
        }
    }

    // MARK: - Strength

    private static func buildStrengthDashboard(
        processed: ProcessedData,
        pinnedLifts: [String],
        filter: StatsExerciseFilter,
        preferredUnit: WorkoutUnits,
        range: StatsRange,
        calendar: Calendar
    ) -> StatsDashboardResult {
        let weeks = processed.rangeWeeks
        let laRTSeries = aggregateExerciseSeries(processed.weeklyLaRTByExercise, pinned: pinnedLifts, filter: filter, weeks: weeks)
        let topSetSeries = aggregateExerciseSeries(processed.weeklyTopSetByExercise, pinned: pinnedLifts, filter: filter, weeks: weeks)
        let overloadSeries = weeklySeries(from: processed.weeklyOverloadEvents, weeks: weeks)
        let restSeries = weeklySeries(from: processed.weeklyMedianRest, weeks: weeks)
        let coverageTrend = coverageSeries(processed: processed, weeks: weeks)
        let balanceTrend = balanceSeries(processed.weeklyPushPull, weeks: weeks)

        let laRTBaseline = StatsBaselineEngine.baseline(series: laRTSeries)
        let overloadBaseline = StatsBaselineEngine.baseline(series: overloadSeries, defaultFloor: 3)
        let restBaseline = StatsBaselineEngine.baseline(series: restSeries)
        let topSetBaseline = StatsBaselineEngine.baseline(series: topSetSeries)
        let coverageBaseline = StatsBaselineEngine.baseline(series: coverageTrend, defaultFloor: 4)
        let balanceBaseline = defaultBalanceBaseline(series: balanceTrend)

        let laRTCard = TrendCardModel(
            metric: .strengthCapacity,
            title: "Heaviest lift",
            primaryValue: weightText(laRTSeries.last?.value ?? 0, unit: preferredUnit),
            rawValue: laRTSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: laRTSeries.last?.value ?? 0, previous: laRTSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(laRTBaseline),
            streakText: friendlyStreak(laRTBaseline),
            context: "Your strongest weight this week"
        )

        let topSetCard = TrendCardModel(
            metric: .topSetOutput,
            title: "Best performance",
            primaryValue: formatNumber(topSetSeries.last?.value ?? 0),
            rawValue: topSetSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: topSetSeries.last?.value ?? 0, previous: topSetSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(topSetBaseline),
            streakText: friendlyStreak(topSetBaseline),
            context: "Top weight × reps combo"
        )

        let overloadCard = TrendCardModel(
            metric: .overloadEvents,
            title: "New records",
            primaryValue: "\(Int(overloadSeries.last?.value ?? 0)) this wk",
            rawValue: overloadSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: overloadSeries.last?.value ?? 0, previous: overloadSeries.dropLast().last?.value ?? 0),
            comparisonText: "Personal records this week",
            streakText: friendlyStreak(overloadBaseline),
            context: "Times you beat a previous best"
        )

        let restValue = restSeries.last?.value ?? 0
        let restCard = TrendCardModel(
            metric: .restDiscipline,
            title: "Rest time",
            primaryValue: String(format: "%.0fs", restValue),
            rawValue: restValue,
            direction: StatsBaselineEngine.trend(current: restValue, previous: restSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(restBaseline),
            streakText: friendlyStreak(restBaseline),
            context: "Average break between sets"
        )

        let cards = [laRTCard, topSetCard, overloadCard, restCard]

        let minimumStrip: [MinimumStripMetric] = [
            MinimumStripMetric(metric: .workload, title: "Total work", weekly: weeklySeries(from: processed.weeklyTonnage, weeks: weeks), baseline: StatsBaselineEngine.baseline(series: weeklySeries(from: processed.weeklyTonnage, weeks: processed.weeks))),
            MinimumStripMetric(metric: .progressEvents, title: "New records", weekly: overloadSeries, baseline: overloadBaseline),
            MinimumStripMetric(metric: .coverage, title: "Muscle groups", weekly: coverageTrend, baseline: coverageBaseline),
            MinimumStripMetric(metric: .balance, title: "Balance", weekly: balanceTrend, baseline: balanceBaseline),
            MinimumStripMetric(metric: .efficiency, title: "Training pace", weekly: weeklySeries(from: processed.weeklyDensity, weeks: weeks), baseline: StatsBaselineEngine.baseline(series: weeklySeries(from: processed.weeklyDensity, weeks: processed.weeks)))
        ]

        let sections: [StatsSectionModel] = [
            StatsSectionModel(
                metric: .strengthCapacity,
                title: "Strength over time",
                description: "Your heaviest lift each week",
                series: laRTSeries,
                baseline: laRTBaseline,
                breakdown: breakdownTopExercises(from: processed.weeklyLaRTByExercise, weeks: weeks, preferredUnit: preferredUnit)
            ),
            StatsSectionModel(
                metric: .overloadEvents,
                title: "Personal records",
                description: "Times you beat a previous best",
                series: overloadSeries,
                baseline: overloadBaseline,
                breakdown: []
            ),
            StatsSectionModel(
                metric: .restDiscipline,
                title: "Rest between sets",
                description: "Average break time",
                series: restSeries,
                baseline: restBaseline,
                breakdown: []
            ),
            StatsSectionModel(
                metric: .topSetOutput,
                title: "Rep range breakdown",
                description: "How your sets are distributed",
                series: topSetSeries,
                baseline: topSetBaseline,
                breakdown: repDistributionBreakdown(from: processed.weeklyRepExposure, weeks: weeks)
            )
        ]

        let alerts = strengthAlerts(laRTSeries: laRTSeries, repExposure: processed.weeklyRepExposure, weeks: weeks, restSeries: restSeries)

        let muscles = muscleOverview(from: processed, weeks: weeks)

        let detail: [StatsMetricKind: MetricDetailModel] = [
            .strengthCapacity: MetricDetailModel(metric: .strengthCapacity, title: "Heaviest Lift", series: laRTSeries, baseline: laRTBaseline, contextLines: ["Your strongest weight each week."], breakdown: breakdownTopExercises(from: processed.weeklyLaRTByExercise, weeks: weeks, preferredUnit: preferredUnit), learnMore: ["We track your best load at 5+ reps (called LaRT-5). Your baseline is calculated from the past 8 weeks to show if you're above or below your usual strength level."] ),
            .topSetOutput: MetricDetailModel(metric: .topSetOutput, title: "Best Performance", series: topSetSeries, baseline: topSetBaseline, contextLines: ["Your top weight × reps combo each week."], breakdown: breakdownTopExercises(from: processed.weeklyTopSetByExercise, weeks: weeks, preferredUnit: preferredUnit), learnMore: ["This measures your best single set performance by multiplying weight times reps. It helps you see if you're getting stronger even when using different rep ranges."]),
            .overloadEvents: MetricDetailModel(metric: .overloadEvents, title: "New Records", series: overloadSeries, baseline: overloadBaseline, contextLines: ["Times you beat a previous best."], breakdown: [], learnMore: ["Every time you beat your best weight for a given rep range, we count it as a record. More records means you're making steady progress."]),
            .restDiscipline: MetricDetailModel(metric: .restDiscipline, title: "Rest Time", series: restSeries, baseline: restBaseline, contextLines: ["Average break between heavy sets."], breakdown: [], learnMore: ["We calculate the typical rest you take between heavy sets (6 reps or fewer). Longer rest helps with strength, but if it's creeping up while performance drops, you might be overreaching."])
        ]

        return StatsDashboardResult(mode: .strength, range: range, filter: filter, cards: cards, minimumStrip: minimumStrip, sections: sections, alerts: alerts, muscles: muscles, detail: detail)
    }

    // MARK: - Hypertrophy

    private static func buildHypertrophyDashboard(
        processed: ProcessedData,
        pinnedLifts: [String],
        filter: StatsExerciseFilter,
        preferredUnit: WorkoutUnits,
        range: StatsRange,
        calendar: Calendar
    ) -> StatsDashboardResult {
        let weeks = processed.rangeWeeks
        let hardSetsSeries = weeklyMuscleMinSeries(from: processed.weeklyHardSetsByMuscle, weeks: weeks)
        let tonnageSeries = weeklySeries(from: processed.weeklyTonnage, weeks: weeks)
        let coverage = coverageSeries(processed: processed, weeks: weeks)
        let varietyBreakdown = varietyBreakdown(items: processed.exerciseVarietyByMuscle)
        let balanceTrend = balanceSeries(processed.weeklyPushPull, weeks: weeks)

        let hardSetsBaseline = StatsBaselineEngine.baseline(series: hardSetsSeries, defaultFloor: 8)
        let tonnageBaseline = StatsBaselineEngine.baseline(series: tonnageSeries)
        let coverageBaseline = StatsBaselineEngine.baseline(series: coverage)
        let balanceBaseline = defaultBalanceBaseline(series: balanceTrend)

        let lowestMuscle = lowestMuscleSet(from: processed.weeklyHardSetsByMuscle, weeks: weeks)
        let hardSetsCard = TrendCardModel(
            metric: .hardSets,
            title: "Growth sets",
            primaryValue: "\(lowestMuscle.value) sets",
            rawValue: Double(lowestMuscle.value),
            direction: StatsBaselineEngine.trend(current: hardSetsSeries.last?.value ?? 0, previous: hardSetsSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(hardSetsBaseline),
            streakText: friendlyStreak(hardSetsBaseline),
            context: "\(lowestMuscle.muscle.displayName) got the least work"
        )

        let volumeCard = TrendCardModel(
            metric: .weeklyVolume,
            title: "Total work",
            primaryValue: weightText(tonnageSeries.last?.value ?? 0, unit: preferredUnit, isTonnage: true),
            rawValue: tonnageSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: tonnageSeries.last?.value ?? 0, previous: tonnageSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(tonnageBaseline),
            streakText: friendlyStreak(tonnageBaseline),
            context: "All weight moved this week"
        )

        let coverageCard = TrendCardModel(
            metric: .coverage,
            title: "Muscles trained",
            primaryValue: "\(Int(coverage.last?.value ?? 0))/\(MuscleGroup.allCases.count)",
            rawValue: coverage.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: coverage.last?.value ?? 0, previous: coverage.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(coverageBaseline),
            streakText: friendlyStreak(coverageBaseline),
            context: "Groups that hit your target"
        )

        let varietyPrimary = varietyBreakdown.first
        let varietyRaw = Double(varietyPrimary?.valueText.components(separatedBy: " ").first ?? "") ?? 0
        let varietyCard = TrendCardModel(
            metric: .variety,
            title: "Exercise variety",
            primaryValue: varietyPrimary?.valueText ?? "—",
            rawValue: varietyRaw,
            direction: .flat,
            comparisonText: "Best: 2-4 exercises per muscle",
            streakText: "Past 4 weeks",
            context: varietyPrimary?.title ?? "Mix"
        )

        let cards = [hardSetsCard, volumeCard, coverageCard, varietyCard]

        let overloadSeries = weeklySeries(from: processed.weeklyOverloadEvents, weeks: weeks)
        let overloadBaseline = StatsBaselineEngine.baseline(series: overloadSeries, defaultFloor: 3)

        let minimumStrip: [MinimumStripMetric] = [
            MinimumStripMetric(metric: .workload, title: "Total work", weekly: tonnageSeries, baseline: tonnageBaseline),
            MinimumStripMetric(metric: .progressEvents, title: "New records", weekly: overloadSeries, baseline: overloadBaseline),
            MinimumStripMetric(metric: .coverage, title: "Muscle groups", weekly: coverage, baseline: coverageBaseline),
            MinimumStripMetric(metric: .balance, title: "Balance", weekly: balanceTrend, baseline: balanceBaseline),
            MinimumStripMetric(metric: .efficiency, title: "Training pace", weekly: weeklySeries(from: processed.weeklyDensity, weeks: weeks), baseline: StatsBaselineEngine.baseline(series: weeklySeries(from: processed.weeklyDensity, weeks: processed.weeks)))
        ]

        let junkBreakdown = processed.junk.byExercise
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { BreakdownItem(title: $0.key, valueText: "\($0.value) sets", detail: nil) }

        let sections: [StatsSectionModel] = [
            StatsSectionModel(metric: .hardSets, title: "Growth sets per muscle", description: "Working sets for each group", series: hardSetsSeries, baseline: hardSetsBaseline, breakdown: muscleBreakdown(from: processed.weeklyHardSetsByMuscle, weeks: weeks)),
            StatsSectionModel(metric: .weeklyVolume, title: "Total weight moved", description: "All your training volume", series: tonnageSeries, baseline: tonnageBaseline, breakdown: []),
            StatsSectionModel(metric: .junkVolume, title: "Too-light sets", description: "Sets that might not do much", series: [WeeklyMetricValue(weekStart: weeks.last ?? Date(), value: Double(processed.junk.totalJunkSets))], baseline: nil, breakdown: junkBreakdown),
            StatsSectionModel(metric: .variety, title: "Exercise variety", description: "Different movements per muscle", series: [], baseline: nil, breakdown: varietyBreakdown)
        ]

        let alerts = hypertrophyAlerts(hardSetsSeries: hardSetsSeries, junk: processed.junk.totalJunkSets, overloadSeries: overloadSeries)

        let muscles = muscleOverview(from: processed, weeks: weeks)

        let detail: [StatsMetricKind: MetricDetailModel] = [
            .hardSets: MetricDetailModel(metric: .hardSets, title: "Growth Sets", series: hardSetsSeries, baseline: hardSetsBaseline, contextLines: ["Working sets that build muscle (5-30 reps)."], breakdown: muscleBreakdown(from: processed.weeklyHardSetsByMuscle, weeks: weeks), learnMore: ["Growth sets are any working sets between 5-30 reps. Your baseline is based on your lowest muscle group over the past 8 weeks to help you maintain balance."]),
            .weeklyVolume: MetricDetailModel(metric: .weeklyVolume, title: "Total Work", series: tonnageSeries, baseline: tonnageBaseline, contextLines: ["All weight you moved this week."], breakdown: [], learnMore: ["This is your total training volume: weight multiplied by reps for every set (warmups excluded). More volume generally means more stimulus, but recovery matters too."]),
            .coverage: MetricDetailModel(metric: .coverage, title: "Muscles Trained", series: coverage, baseline: coverageBaseline, contextLines: ["Muscle groups that hit your weekly target."], breakdown: [], learnMore: ["A muscle counts as 'covered' if you either hit its minimum set count or trained it on 2+ different days. This helps you stay balanced."]),
            .variety: MetricDetailModel(metric: .variety, title: "Exercise Variety", series: [], baseline: nil, contextLines: ["Different movements you used per muscle."], breakdown: varietyBreakdown, learnMore: ["Best results come from 2-4 different exercises per muscle over 4 weeks. Too few limits development, too many can dilute your focus."]),
            .junkVolume: MetricDetailModel(metric: .junkVolume, title: "Too-Light Sets", series: [], baseline: nil, contextLines: ["Sets that probably didn't challenge you much."], breakdown: junkBreakdown, learnMore: ["We flag sets that are much lighter than your usual for that rep range (less than 70% of your rolling median). These sets might not be hard enough to drive adaptation. Note: deload weeks are automatically excluded."])
        ]

        return StatsDashboardResult(mode: .hypertrophy, range: range, filter: filter, cards: cards, minimumStrip: minimumStrip, sections: sections, alerts: alerts, muscles: muscles, detail: detail)
    }

    // MARK: - Athletic

    private static func buildAthleticDashboard(
        processed: ProcessedData,
        pinnedLifts: [String],
        filter: StatsExerciseFilter,
        preferredUnit: WorkoutUnits,
        range: StatsRange,
        calendar: Calendar
    ) -> StatsDashboardResult {
        let weeks = processed.rangeWeeks
        let densitySeries = weeklySeries(from: processed.weeklyDensity, weeks: weeks)
        let hardSetSeries = weeklySeries(from: processed.weeklyHardSets.mapValues { Double($0) }, weeks: weeks)
        let tonnageSeries = weeklySeries(from: processed.weeklyTonnage, weeks: weeks)
        let overloadSeries = weeklySeries(from: processed.weeklyOverloadEvents, weeks: weeks)
        let coverageTrend = coverageSeries(processed: processed, weeks: weeks)
        let balanceTrend = balanceSeries(processed.weeklyPushPull, weeks: weeks)

        let laRTSeries = aggregateExerciseSeries(processed.weeklyLaRTByExercise, pinned: pinnedLifts, filter: filter, weeks: weeks)

        let densityBaseline = StatsBaselineEngine.baseline(series: densitySeries)
        let hardSetBaseline = StatsBaselineEngine.baseline(series: hardSetSeries)
        let tonnageBaseline = StatsBaselineEngine.baseline(series: tonnageSeries)
        let laRTBaseline = StatsBaselineEngine.baseline(series: laRTSeries)
        let balanceBaseline = defaultBalanceBaseline(series: balanceTrend)

        let workCapacityCard = TrendCardModel(
            metric: .density,
            title: "Training pace",
            primaryValue: formatNumber(densitySeries.last?.value ?? 0) + " / min",
            rawValue: densitySeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: densitySeries.last?.value ?? 0, previous: densitySeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(densityBaseline),
            streakText: friendlyStreak(densityBaseline),
            context: "How much you moved per minute"
        )

        let strengthCard = TrendCardModel(
            metric: .strengthCapacity,
            title: "Strength anchor",
            primaryValue: weightText(laRTSeries.last?.value ?? 0, unit: preferredUnit),
            rawValue: laRTSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: laRTSeries.last?.value ?? 0, previous: laRTSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(laRTBaseline),
            streakText: friendlyStreak(laRTBaseline),
            context: "Your heaviest lift this week"
        )

        let hypertrophyCard = TrendCardModel(
            metric: .hypertrophyDose,
            title: "Growth volume",
            primaryValue: "\(Int(hardSetSeries.last?.value ?? 0)) sets",
            rawValue: hardSetSeries.last?.value ?? 0,
            direction: StatsBaselineEngine.trend(current: hardSetSeries.last?.value ?? 0, previous: hardSetSeries.dropLast().last?.value ?? 0),
            comparisonText: friendlyStatus(hardSetBaseline),
            streakText: friendlyStreak(hardSetBaseline),
            context: "Hard sets for muscle building"
        )

        let balanceCard = TrendCardModel(
            metric: .balance,
            title: "Push/pull balance",
            primaryValue: balanceValueText(balanceTrend.last?.value ?? 0),
            rawValue: balanceTrend.last?.value ?? 0,
            direction: .flat,
            comparisonText: "Push vs pull • Quad vs hinge",
            streakText: "Aim for even split",
            context: "1.0 means perfectly balanced"
        )

        let cards = [workCapacityCard, strengthCard, hypertrophyCard, balanceCard]

        let minimumStrip: [MinimumStripMetric] = [
            MinimumStripMetric(metric: .workload, title: "Total work", weekly: tonnageSeries, baseline: tonnageBaseline),
            MinimumStripMetric(metric: .progressEvents, title: "New records", weekly: overloadSeries, baseline: StatsBaselineEngine.baseline(series: overloadSeries, defaultFloor: 3)),
            MinimumStripMetric(metric: .coverage, title: "Muscle groups", weekly: coverageTrend, baseline: StatsBaselineEngine.baseline(series: coverageTrend, defaultFloor: 4)),
            MinimumStripMetric(metric: .balance, title: "Balance", weekly: balanceTrend, baseline: balanceBaseline),
            MinimumStripMetric(metric: .efficiency, title: "Training pace", weekly: densitySeries, baseline: densityBaseline)
        ]

        let sections: [StatsSectionModel] = [
            StatsSectionModel(metric: .workload, title: "Total weight moved", description: "All training volume this week", series: tonnageSeries, baseline: tonnageBaseline, breakdown: []),
            StatsSectionModel(metric: .density, title: "Training pace", description: "Work per minute", series: densitySeries, baseline: densityBaseline, breakdown: []),
            StatsSectionModel(metric: .overloadEvents, title: "Personal records", description: "New bests logged", series: overloadSeries, baseline: StatsBaselineEngine.baseline(series: overloadSeries, defaultFloor: 3), breakdown: []),
            StatsSectionModel(metric: .balance, title: "Push/pull balance", description: "Push vs pull • Quad vs hinge", series: balanceTrend, baseline: balanceBaseline, breakdown: balanceBreakdown(processed.weeklyPushPull, processed.weeklyQuadHinge, weeks: weeks))
        ]

        let alerts = athleticAlerts(densitySeries: densitySeries, balanceSeries: balanceTrend, overloadSeries: overloadSeries, tonnageSeries: tonnageSeries)

        let muscles = muscleOverview(from: processed, weeks: weeks)

        let detail: [StatsMetricKind: MetricDetailModel] = [
            .density: MetricDetailModel(metric: .density, title: "Training Pace", series: densitySeries, baseline: densityBaseline, contextLines: ["How much work you did per minute."], breakdown: [], learnMore: ["Training pace is calculated by dividing your total weekly volume by minutes trained. Higher pace means you're getting more done in less time, which can be useful for conditioning or time-efficient training."]),
            .strengthCapacity: MetricDetailModel(metric: .strengthCapacity, title: "Strength Anchor", series: laRTSeries, baseline: laRTBaseline, contextLines: ["Your heaviest lift this week."], breakdown: breakdownTopExercises(from: processed.weeklyLaRTByExercise, weeks: weeks, preferredUnit: preferredUnit), learnMore: ["We track your best load at 5+ reps as your strength anchor. This gives you one clear number to gauge if your strength is holding steady or improving. Your baseline comes from the past 8 weeks."]),
            .hypertrophyDose: MetricDetailModel(metric: .hypertrophyDose, title: "Growth Volume", series: hardSetSeries, baseline: hardSetBaseline, contextLines: ["Total growth sets this week (5-30 reps)."], breakdown: muscleBreakdown(from: processed.weeklyHardSetsByMuscle, weeks: weeks), learnMore: ["Growth volume counts all working sets between 5-30 reps. Warmups are excluded. Your baseline is based on the past 8 weeks to help you stay consistent."]),
            .balance: MetricDetailModel(metric: .balance, title: "Push/Pull Balance", series: balanceTrend, baseline: balanceBaseline, contextLines: ["Push vs pull and quad vs hinge ratio."], breakdown: balanceBreakdown(processed.weeklyPushPull, processed.weeklyQuadHinge, weeks: weeks), learnMore: ["A healthy balance is between 0.7 and 1.3 for both push:pull and quad:hinge. This helps prevent muscle imbalances and keeps your training sustainable long-term."])
        ]

        return StatsDashboardResult(mode: .athletic, range: range, filter: filter, cards: cards, minimumStrip: minimumStrip, sections: sections, alerts: alerts, muscles: muscles, detail: detail)
    }

    // MARK: - Processing

    private static func processSessions(
        sessions: [SessionData],
        range: StatsRange,
        now: Date,
        calendar: Calendar
    ) -> ProcessedData {
        let extendedInterval = range.extendedInterval(extraWeeks: 8, now: now, calendar: calendar)
        let rangeInterval = range.dateInterval(now: now, calendar: calendar)
        let weeks = range.weekStarts(now: now, calendar: calendar, includePadding: 8)
        let rangeWeeks = range.weekStarts(now: now, calendar: calendar)

        var weeklyTonnage: [Date: Double] = [:]
        var weeklyHardSets: [Date: Int] = [:]
        var weeklyHardSetsByMuscle: [Date: [MuscleGroup: Int]] = [:]
        var weeklyOverloadEvents: [Date: Int] = [:]
        var weeklyTopSetByExercise: [Date: [String: Double]] = [:]
        var weeklyLaRTByExercise: [Date: [String: Double]] = [:]
        var weeklyRestSamples: [Date: [Double]] = [:]
        var weeklyPushPull: [Date: (push: Int, pull: Int)] = [:]
        var weeklyQuadHinge: [Date: (quad: Int, hinge: Int)] = [:]
        var weeklyRepExposure: [Date: [RepBucket: Int]] = [:]
        var weeklyCoverageTouches: [Date: [MuscleGroup: Set<Date>]] = [:]
        var exerciseVarietyByMuscle: [MuscleGroup: Set<String>] = [:]
        var weeklyDensitySamples: [Date: [Double]] = [:]
        var weeklyHardSetDensitySamples: [Date: [Double]] = [:]
        var hardSetContributors: [MuscleGroup: [String: Int]] = [:]

        var bestByExerciseBucket: [String: Double] = [:]
        var lastHeavySetTimestamp: [String: Date] = [:]
        var bucketWeights: [String: [JunkBucket: [Date: [Double]]]] = [:]
        var junkCandidates: [JunkCandidate] = []
        var sessionAccumulators: [UUID: SessionAccumulator] = [:]

        let filteredSessions = sessions.filter { session in
            guard session.isHidden == false, let ended = session.endedAt else { return false }
            return ended >= extendedInterval.start && ended <= extendedInterval.end && session.totalSets > 0
        }

        let sortedSessions = filteredSessions.sorted { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }

        for session in sortedSessions {
            guard let endedAt = session.endedAt else { continue }
            let weekStart = DateRanges.startOfWeekMonday(for: endedAt, calendar: calendar)

            sessionAccumulators[session.id] = SessionAccumulator(durationSeconds: session.durationSeconds, endedAt: endedAt)

            for exercise in session.exercises {
                let normalized = normalizeExerciseName(exercise.name)
                let displayName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let muscleInfo = StatsMuscleMapper.info(for: exercise.name)

                for set in exercise.sets.sorted(by: { $0.createdAt < $1.createdAt }) {
                    let isWarmup = SetTag(rawValue: set.tagRaw) == .W
                    let isWorking = !isWarmup && set.reps > 0
                    let reps = max(0, set.reps)
                    let weight = max(0, set.weightKg ?? 0)
                    let tonnage = isWorking ? weight * Double(reps) : 0

                    if var acc = sessionAccumulators[session.id] {
                        acc.tonnage += tonnage
                        if isWorking && (5...30).contains(reps) { acc.hardSets += 1 }
                        if acc.firstSetAt == nil { acc.firstSetAt = set.createdAt }
                        acc.lastSetAt = set.createdAt
                        sessionAccumulators[session.id] = acc
                    }

                    if !isWorking { continue }

                    weeklyTonnage[weekStart, default: 0] += tonnage
                    weeklyRepExposure[weekStart, default: [:]][repBucket(for: reps), default: 0] += 1

                    if (5...30).contains(reps) {
                        weeklyHardSets[weekStart, default: 0] += 1
                        weeklyHardSetsByMuscle[weekStart, default: [:]][muscleInfo.primary, default: 0] += 1
                        weeklyCoverageTouches[weekStart, default: [:]][muscleInfo.primary, default: []].insert(calendar.startOfDay(for: endedAt))
                        exerciseVarietyByMuscle[muscleInfo.primary, default: []].insert(normalized)
                        hardSetContributors[muscleInfo.primary, default: [:]][displayName, default: 0] += 1
                        for secondary in muscleInfo.secondary {
                            weeklyHardSetsByMuscle[weekStart, default: [:]][secondary, default: 0] += 1
                            weeklyCoverageTouches[weekStart, default: [:]][secondary, default: []].insert(calendar.startOfDay(for: endedAt))
                            exerciseVarietyByMuscle[secondary, default: []].insert(normalized)
                            hardSetContributors[secondary, default: [:]][displayName, default: 0] += 1
                        }

                        if let bucket = JunkBucket.from(reps: reps) {
                            bucketWeights[normalized, default: [:]][bucket, default: [:]][weekStart, default: []].append(weight)
                            let candidate = JunkCandidate(exerciseId: normalized, exerciseName: exercise.name, week: weekStart, weight: weight, bucket: bucket, inRange: rangeInterval.contains(endedAt))
                            junkCandidates.append(candidate)
                        }
                    }

                    // Overload events
                    let bucketKey = "\(normalized)-\(overloadBucket(for: reps))"
                    let score = tonnage
                    let best = bestByExerciseBucket[bucketKey] ?? 0
                    if score > best * 1.01 {
                        weeklyOverloadEvents[weekStart, default: 0] += 1
                        bestByExerciseBucket[bucketKey] = score
                    }

                    // Top set output
                    weeklyTopSetByExercise[weekStart, default: [:]][normalized] = max(weeklyTopSetByExercise[weekStart, default: [:]][normalized] ?? 0, score)

                    // LaRT-5
                    if reps >= 5 {
                        weeklyLaRTByExercise[weekStart, default: [:]][normalized] = max(weeklyLaRTByExercise[weekStart, default: [:]][normalized] ?? 0, weight)
                    }

                    // Rest discipline
                    if reps <= 6 {
                        let key = "\(session.id.uuidString)-\(normalized)"
                        if let last = lastHeavySetTimestamp[key] {
                            let rest = set.createdAt.timeIntervalSince(last)
                            if rest > 15 && rest < 1200 {
                                weeklyRestSamples[weekStart, default: []].append(rest)
                            }
                        }
                        lastHeavySetTimestamp[key] = set.createdAt
                    }

                    // Balance
                    if muscleInfo.balance.contains(.push) { weeklyPushPull[weekStart, default: (0, 0)].push += 1 }
                    if muscleInfo.balance.contains(.pull) { weeklyPushPull[weekStart, default: (0, 0)].pull += 1 }
                    if muscleInfo.balance.contains(.quad) { weeklyQuadHinge[weekStart, default: (0, 0)].quad += 1 }
                    if muscleInfo.balance.contains(.hinge) { weeklyQuadHinge[weekStart, default: (0, 0)].hinge += 1 }
                }
            }
        }

        // Session densities
        for (id, acc) in sessionAccumulators {
            var durationSeconds = acc.durationSeconds
            if durationSeconds == nil, let first = acc.firstSetAt, let last = acc.lastSetAt {
                durationSeconds = Int(last.timeIntervalSince(first))
            }
            if durationSeconds == nil {
                durationSeconds = 45 * 60
            }
            let minutes = max(1, Double(durationSeconds ?? 0) / 60.0)
            let density = acc.tonnage / minutes
            let hardSetDensity = Double(acc.hardSets) / minutes
            let week = DateRanges.startOfWeekMonday(for: acc.endedAt, calendar: calendar)
            weeklyDensitySamples[week, default: []].append(density)
            weeklyHardSetDensitySamples[week, default: []].append(hardSetDensity)
        }

        let weeklyDensity = weeklyDensitySamples.mapValues { average($0) }
        let weeklyHardSetDensity = weeklyHardSetDensitySamples.mapValues { average($0) }
        let weeklyMedianRest = weeklyRestSamples.mapValues { median($0) }

        let tonnageSeries = weeks.sorted().map { weeklyTonnage[$0, default: 0] }
        let deloadWeeks = detectDeloadWeeks(weeks: weeks, tonnageSeries: tonnageSeries, mapped: weeklyTonnage)
        let junkSummary = computeJunkSummary(
            candidates: junkCandidates,
            bucketWeights: bucketWeights,
            deloadWeeks: deloadWeeks,
            weeks: weeks
        )

        return ProcessedData(
            weeks: weeks,
            rangeWeeks: rangeWeeks,
            weeklyTonnage: weeklyTonnage,
            weeklyHardSets: weeklyHardSets,
            weeklyHardSetsByMuscle: weeklyHardSetsByMuscle,
            hardSetContributors: hardSetContributors,
            weeklyOverloadEvents: weeklyOverloadEvents,
            weeklyTopSetByExercise: weeklyTopSetByExercise,
            weeklyLaRTByExercise: weeklyLaRTByExercise,
            weeklyMedianRest: weeklyMedianRest,
            weeklyPushPull: weeklyPushPull,
            weeklyQuadHinge: weeklyQuadHinge,
            weeklyRepExposure: weeklyRepExposure,
            weeklyDensity: weeklyDensity,
            weeklyHardSetDensity: weeklyHardSetDensity,
            weeklyCoverageTouches: weeklyCoverageTouches,
            exerciseVarietyByMuscle: exerciseVarietyByMuscle,
            junk: junkSummary
        )
    }

    private static func detectDeloadWeeks(weeks: [Date], tonnageSeries: [Double], mapped: [Date: Double]) -> Set<Date> {
        var deload: Set<Date> = []
        let orderedWeeks = weeks.sorted()
        for (index, week) in orderedWeeks.enumerated() {
            guard index >= 4 else { continue }
            let window = orderedWeeks[(index - 4)..<index]
            let avg = average(window.map { mapped[$0] ?? 0 })
            let value = mapped[week] ?? 0
            if avg > 0 && value < avg * 0.7 {
                deload.insert(week)
            }
        }
        return deload
    }

    private static func computeJunkSummary(
        candidates: [JunkCandidate],
        bucketWeights: [String: [JunkBucket: [Date: [Double]]]],
        deloadWeeks: Set<Date>,
        weeks: [Date]
    ) -> JunkSummary {
        var junkCount = 0
        var byExercise: [String: Int] = [:]

        // Precompute rolling medians per exercise/bucket per week
        var rollingMedian: [String: [JunkBucket: [Date: Double]]] = [:]
        for (exerciseId, bucketMap) in bucketWeights {
            for bucket in JunkBucket.allCases {
                guard let weekMap = bucketMap[bucket] else { continue }
                let sortedWeeks = weekMap.keys.sorted()
                var medians: [Date: Double] = [:]
                for (idx, week) in sortedWeeks.enumerated() {
                    let startIndex = max(0, idx - 8)
                    let windowWeeks = sortedWeeks[startIndex..<idx]
                    var windowWeights: [Double] = []
                    for w in windowWeeks {
                        windowWeights.append(contentsOf: weekMap[w] ?? [])
                    }
                    medians[week] = median(windowWeights)
                }
                if rollingMedian[exerciseId] == nil { rollingMedian[exerciseId] = [:] }
                rollingMedian[exerciseId]?[bucket] = medians
            }
        }

        for candidate in candidates where candidate.inRange {
            guard let medianWeight = rollingMedian[candidate.exerciseId]?[candidate.bucket]?[candidate.week], medianWeight > 0 else { continue }
            if deloadWeeks.contains(candidate.week) { continue }
            if candidate.weight < medianWeight * 0.7 {
                junkCount += 1
                byExercise[candidate.exerciseName, default: 0] += 1
            }
        }

        return JunkSummary(totalJunkSets: junkCount, byExercise: byExercise)
    }

    // MARK: - Helpers

    private static func weeklySeries(from map: [Date: Double], weeks: [Date]) -> [WeeklyMetricValue] {
        weeks.sorted().map { week in
            WeeklyMetricValue(weekStart: week, value: map[week, default: 0])
        }
    }

    private static func weeklySeries(from map: [Date: Int], weeks: [Date]) -> [WeeklyMetricValue] {
        weeks.sorted().map { week in
            WeeklyMetricValue(weekStart: week, value: Double(map[week, default: 0]))
        }
    }

    private static func aggregateExerciseSeries(_ map: [Date: [String: Double]], pinned: [String], filter: StatsExerciseFilter, weeks: [Date]) -> [WeeklyMetricValue] {
        let normalizedPinned = pinned.map(normalizeExerciseName)
        return weeks.sorted().map { week in
            let exercises = map[week] ?? [:]
            let filtered: [Double]
            switch filter {
            case .allExercises:
                filtered = Array(exercises.values)
            case .keyLifts:
                filtered = exercises.filter { normalizedPinned.contains($0.key) }.map { $0.value }
            }
            let value = filtered.max() ?? 0
            return WeeklyMetricValue(weekStart: week, value: value)
        }
    }

    private static func coverageSeries(processed: ProcessedData, weeks: [Date]) -> [WeeklyMetricValue] {
        weeks.sorted().map { week in
            let counts = processed.weeklyHardSetsByMuscle[week] ?? [:]
            let touches = processed.weeklyCoverageTouches[week] ?? [:]
            var met = 0
            for muscle in MuscleGroup.allCases {
                let setCount = counts[muscle] ?? 0
                let days = touches[muscle]?.count ?? 0
                let floor = Int(defaultFloor(for: muscle))
                if setCount >= floor || days >= 2 {
                    met += 1
                }
            }
            return WeeklyMetricValue(weekStart: week, value: Double(met))
        }
    }

    private static func muscleOverview(from processed: ProcessedData, weeks: [Date]) -> [MuscleOverviewModel] {
        MuscleGroup.allCases.map { muscle in
            let series = weeks.sorted().map { week in
                WeeklyMetricValue(weekStart: week, value: Double(processed.weeklyHardSetsByMuscle[week]?[muscle] ?? 0))
            }
            let floor = defaultFloor(for: muscle)
            let band = floor...(floor + 6)
            let contributors = processed.hardSetContributors[muscle] ?? [:]
            let top = contributors
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { BreakdownItem(title: $0.key, valueText: "\($0.value) sets", detail: nil) }
            return MuscleOverviewModel(muscle: muscle, weekly: series, floor: floor, band: band, topExercises: top)
        }
        .sorted { $0.muscle.displayName < $1.muscle.displayName }
    }

    private static func muscleBreakdown(from map: [Date: [MuscleGroup: Int]], weeks: [Date]) -> [BreakdownItem] {
        var totals: [MuscleGroup: Int] = [:]
        for week in weeks {
            for (muscle, value) in map[week] ?? [:] {
                totals[muscle, default: 0] += value
            }
        }
        return totals
            .sorted { $0.value > $1.value }
            .map { BreakdownItem(title: $0.key.displayName, valueText: "\($0.value) sets", detail: nil) }
    }

    private static func lowestMuscleSet(from map: [Date: [MuscleGroup: Int]], weeks: [Date]) -> (muscle: MuscleGroup, value: Int) {
        var latestWeek = weeks.sorted().last
        var latestMap: [MuscleGroup: Int] = [:]
        if let week = latestWeek {
            latestMap = map[week] ?? [:]
        }
        let fallback = MuscleGroup.allCases.first ?? .chest
        let sorted = latestMap.sorted { $0.value < $1.value }
        if let lowest = sorted.first {
            return (lowest.key, lowest.value)
        }
        return (fallback, 0)
    }

    private static func weeklyMuscleMinSeries(from map: [Date: [MuscleGroup: Int]], weeks: [Date]) -> [WeeklyMetricValue] {
        weeks.sorted().map { week in
            let values = map[week]?.values.map { $0 } ?? []
            let minValue = values.min() ?? 0
            return WeeklyMetricValue(weekStart: week, value: Double(minValue))
        }
    }

    private static func balanceSeries(_ map: [Date: (push: Int, pull: Int)], weeks: [Date]) -> [WeeklyMetricValue] {
        weeks.sorted().map { week in
            let counts = map[week] ?? (0, 0)
            let ratio = balanceRatio(numerator: counts.push, denominator: counts.pull)
            return WeeklyMetricValue(weekStart: week, value: ratio)
        }
    }

    private static func balanceBreakdown(_ pushPull: [Date: (push: Int, pull: Int)], _ quadHinge: [Date: (quad: Int, hinge: Int)], weeks: [Date]) -> [BreakdownItem] {
        let latest = weeks.sorted().last
        let pp = latest.flatMap { pushPull[$0] } ?? (0, 0)
        let qh = latest.flatMap { quadHinge[$0] } ?? (0, 0)
        return [
            BreakdownItem(title: "Push:Pull", valueText: balanceValueText(balanceRatio(numerator: pp.push, denominator: pp.pull)), detail: "Sets push \(pp.push) / pull \(pp.pull)"),
            BreakdownItem(title: "Quad:Hinge", valueText: balanceValueText(balanceRatio(numerator: qh.quad, denominator: qh.hinge)), detail: "Sets quad \(qh.quad) / hinge \(qh.hinge)")
        ]
    }

    private static func balanceRatio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return numerator > 0 ? 1.5 : 1 }
        return Double(numerator) / Double(denominator)
    }

    private static func defaultBalanceBaseline(series: [WeeklyMetricValue]) -> BaselineResult? {
        let floor = 0.7
        let upper = 1.3
        let current = series.last?.value ?? 0
        let delta = floor > 0 ? (current - floor) / floor : 0
        let streak = StatsBaselineEngine.streakWeeks(series: series, floor: floor)
        return BaselineResult(floor: floor, band: floor...upper, type: .default, streakWeeks: streak, deltaPercent: delta)
    }

    private static func balanceValueText(_ ratio: Double) -> String {
        String(format: "%.2f", ratio)
    }

    private static func repBucket(for reps: Int) -> RepBucket {
        switch reps {
        case ...6: return .oneToSix
        case 7...8: return .fiveToEight
        case 9...15: return .nineToFifteen
        default: return .sixteenToThirty
        }
    }

    private static func overloadBucket(for reps: Int) -> String {
        switch reps {
        case ...6: return "heavy"
        case 7...12: return "moderate"
        default: return "high"
        }
    }

    private static func repDistributionBreakdown(from map: [Date: [RepBucket: Int]], weeks: [Date]) -> [BreakdownItem] {
        var totals: [RepBucket: Int] = [:]
        for week in weeks {
            for (bucket, value) in map[week] ?? [:] {
                totals[bucket, default: 0] += value
            }
        }
        return RepBucket.allCases.map { bucket in
            BreakdownItem(title: bucketLabel(bucket), valueText: "\(totals[bucket, default: 0]) sets", detail: nil)
        }
    }

    private static func bucketLabel(_ bucket: RepBucket) -> String {
        switch bucket {
        case .oneToSix: return "1–6 reps"
        case .fiveToEight: return "5–8 reps"
        case .nineToFifteen: return "9–15 reps"
        case .sixteenToThirty: return "16–30 reps"
        }
    }

    private static func varietyBreakdown(items: [MuscleGroup: Set<String>]) -> [BreakdownItem] {
        items.map { muscle, exercises in
            let value = exercises.count
            let status: String
            if value >= 2 && value <= 4 { status = "in band" } else if value < 2 { status = "low" } else { status = "high" }
            return BreakdownItem(title: muscle.displayName, valueText: "\(value) movements", detail: status)
        }
        .sorted { $0.valueText < $1.valueText }
    }

    private static func breakdownTopExercises(from map: [Date: [String: Double]], weeks: [Date], preferredUnit: WorkoutUnits) -> [BreakdownItem] {
        var totals: [String: Double] = [:]
        for week in weeks {
            for (exercise, value) in map[week] ?? [:] {
                totals[exercise, default: 0] = max(totals[exercise, default: 0], value)
            }
        }
        return totals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { entry in
                BreakdownItem(title: cleanDisplayName(entry.key), valueText: weightText(entry.value, unit: preferredUnit), detail: nil)
            }
    }

    private static func keyLiftContext(from map: [Date: [String: Double]], pinned: [String]) -> String {
        let normalizedPinned = pinned.map(normalizeExerciseName)
        let latestEntry = map.values.flatMap { $0 }.first { entry in
            normalizedPinned.contains(entry.key)
        }
        if let match = latestEntry {
            return cleanDisplayName(match.key)
        }
        if let any = map.values.flatMap({ $0 }).max(by: { $0.value < $1.value }) {
            return cleanDisplayName(any.key)
        }
        return "No key lift logged"
    }

    private static func cleanDisplayName(_ id: String) -> String {
        id.split(separator: "|").first.map(String.init) ?? id
    }

    private static func normalizeExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000.0)
        }
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func weightText(_ value: Double, unit: WorkoutUnits, isTonnage: Bool = false) -> String {
        let converted = unit == .lb ? value * WorkoutSessionFormatter.kgToLb : value
        let formatted = isTonnage ? formatNumber(converted) : String(format: "%.0f", converted)
        return isTonnage ? "\(formatted) \(unit == .lb ? "lb" : "kg")" : "\(formatted) \(unit.label)"
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count % 2 == 0 {
            let mid = sorted.count / 2
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[sorted.count / 2]
        }
    }

    private static func defaultFloor(for muscle: MuscleGroup) -> Double {
        switch muscle {
        case .chest, .back, .legs:
            return 10
        case .shoulders:
            return 8
        case .biceps, .triceps, .core:
            return 6
        }
    }

    private static func filterTitle(_ filter: StatsExerciseFilter) -> String {
        switch filter {
        case .allExercises: return "All exercises"
        case .keyLifts: return "Key lifts"
        }
    }

    private static func friendlyStatus(_ baseline: BaselineResult?) -> String {
        guard let baseline else { return "Need more sessions to judge" }
        if baseline.deltaPercent >= 0 {
            return "Above your usual minimum"
        } else {
            return "Below your usual minimum"
        }
    }

    private static func friendlyStreak(_ baseline: BaselineResult?) -> String {
        guard let baseline else { return "Building consistency" }
        let weeks = max(0, baseline.streakWeeks)
        if weeks == 0 { return "Building consistency" }
        return "Steady for \(weeks) wk\(weeks == 1 ? "" : "s")"
    }

    // MARK: - Alerts

    private static func strengthAlerts(laRTSeries: [WeeklyMetricValue], repExposure: [Date: [RepBucket: Int]], weeks: [Date], restSeries: [WeeklyMetricValue]) -> [AlertModel] {
        var alerts: [AlertModel] = []
        if laRTSeries.suffix(4).allSatisfy({ $0.value <= (laRTSeries.dropLast().last?.value ?? 0) }) && (laRTSeries.last?.value ?? 0) > 0 {
            alerts.append(AlertModel(message: "Strength hasn't moved in a few weeks", metric: .strengthCapacity))
        }
        if let latestWeek = weeks.sorted().last {
            let heavySets = repExposure[latestWeek]?[.oneToSix] ?? 0
            if heavySets < 5 {
                alerts.append(AlertModel(message: "Not enough heavy sets this week", metric: .topSetOutput))
            }
        }
        if let rest = restSeries.last, let prev = restSeries.dropLast().last, rest.value > prev.value * 1.15, (laRTSeries.last?.value ?? 0) <= (laRTSeries.dropLast().last?.value ?? 0) {
            alerts.append(AlertModel(message: "Rest times getting longer without gains", metric: .restDiscipline))
        }
        return alerts
    }

    private static func hypertrophyAlerts(hardSetsSeries: [WeeklyMetricValue], junk: Int, overloadSeries: [WeeklyMetricValue]) -> [AlertModel] {
        var alerts: [AlertModel] = []
        if hardSetsSeries.last?.value ?? 0 < 8 {
            alerts.append(AlertModel(message: "Below minimum growth volume", metric: .hardSets))
        }
        if junk > 0 {
            alerts.append(AlertModel(message: "Some sets were too light", metric: .junkVolume))
        }
        if let volume = overloadSeries.last, volume.value < (overloadSeries.dropLast().last?.value ?? 0) {
            alerts.append(AlertModel(message: "Doing more volume but fewer PRs", metric: .overloadEvents))
        }
        return alerts
    }

    private static func athleticAlerts(densitySeries: [WeeklyMetricValue], balanceSeries: [WeeklyMetricValue], overloadSeries: [WeeklyMetricValue], tonnageSeries: [WeeklyMetricValue]) -> [AlertModel] {
        var alerts: [AlertModel] = []
        if let latestBalance = balanceSeries.last, latestBalance.value < 0.7 || latestBalance.value > 1.3 {
            alerts.append(AlertModel(message: "Balance needs attention", metric: .balance))
        }
        if let latestTonnage = tonnageSeries.last, let prevTonnage = tonnageSeries.dropLast().last, let latestDensity = densitySeries.last, latestTonnage.value > prevTonnage.value, latestDensity.value < (densitySeries.dropLast().last?.value ?? 0) {
            alerts.append(AlertModel(message: "Training volume up but pace down", metric: .density))
        }
        if overloadSeries.suffix(3).allSatisfy({ $0.value < 2 }) {
            alerts.append(AlertModel(message: "Not seeing much progress lately", metric: .overloadEvents))
        }
        return alerts
    }

#if DEBUG
    static func debugJunkSummary(sessions: [SessionData], range: StatsRange, now: Date = Date()) -> JunkSummary {
        processSessions(sessions: sessions, range: range, now: now, calendar: DateRanges.isoCalendar()).junk
    }
#endif
}
