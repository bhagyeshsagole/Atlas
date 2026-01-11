import Foundation

struct MuscleCoverageScoring {
    static func computeBucketScores(
        sessions: [WorkoutSession],
        range: StatsLens,
        calendar: Calendar = .current
    ) -> [MuscleGroup: BucketScore] {
        let filtered = filterSessions(sessions, for: range, calendar: calendar)
        var setCounts: [MuscleGroup: Int] = [:]
        var daysPerBucket: [MuscleGroup: Set<Date>] = [:]
        var coveredTags: [MuscleGroup: Set<MovementTag>] = [:]

        var workingSetCount = 0
        for session in filtered {
            guard let ended = session.endedAt else { continue }
            for exercise in session.exercises {
                let mapping = classify(exerciseName: exercise.name)
                for set in exercise.sets {
                    guard set.reps > 0 else { continue }
                    workingSetCount += 1
                    for bucket in mapping.buckets {
                        setCounts[bucket, default: 0] += 1
                        daysPerBucket[bucket, default: []].insert(calendar.startOfDay(for: ended))
                    }
                    for tag in mapping.tags {
                        for bucket in mapping.buckets {
                            coveredTags[bucket, default: []].insert(tag)
                        }
                    }
                }
            }
        }

        var scores: [MuscleGroup: BucketScore] = [:]
        for bucket in MuscleGroup.allCases {
            let hardSets = setCounts[bucket] ?? 0
            let days = daysPerBucket[bucket]?.count ?? 0
            let tagsCovered = coveredTags[bucket] ?? []
            let (score, missingTags, reasons, suggestions) = scoreForBucket(bucket: bucket, hardSets: hardSets, days: days, covered: tagsCovered, range: range)
            let progress = min(1.0, Double(score) / 10.0)
            scores[bucket] = BucketScore(
                bucket: bucket,
                score0to10: score,
                progress01: progress,
                coveredTags: Array(tagsCovered),
                missingTags: missingTags,
                hardSets: hardSets,
                trainingDays: days,
                reasons: reasons,
                suggestions: suggestions
            )
        }
        #if DEBUG
        let totalSets = setCounts.values.reduce(0, +)
        print("[STATS][MUSCLE] range=\(range.rawValue) sessions=\(filtered.count) workingSets=\(workingSetCount) totalBucketSets=\(totalSets)")
        #endif
        return scores
    }

    private static func filterSessions(_ sessions: [WorkoutSession], for range: StatsLens, calendar: Calendar) -> [WorkoutSession] {
        let now = Date()
        let start: Date?
        let end: Date?
        switch range {
        case .week:
            let range = DateRanges.weekRangeMonday(for: now, calendar: DateRanges.isoCalendar())
            start = range.lowerBound
            end = range.upperBound
        case .month:
            end = now
            start = calendar.date(byAdding: .day, value: -30, to: now)
        case .all:
            start = nil
            end = nil
        }
        return sessions.filter { session in
            guard let ended = session.endedAt, session.totalSets > 0 else { return false }
            if let start {
                if let end {
                    return ended >= start && ended <= end
                }
                return ended >= start
            }
            return true
        }
    }

    private static func classify(exerciseName: String) -> (buckets: [MuscleGroup], tags: [MovementTag]) {
        let lower = exerciseName.lowercased()
        var buckets: [MuscleGroup] = []
        var tags: [MovementTag] = []

        func add(_ bucket: MuscleGroup, _ tag: MovementTag) {
            if !buckets.contains(bucket) { buckets.append(bucket) }
            tags.append(tag)
        }

        let musclePair = ExerciseMuscleMap.muscles(for: exerciseName)
        if musclePair.primary.lowercased().contains("chest") { add(.chest, .horizontalPress) }
        if musclePair.primary.lowercased().contains("back") { add(.back, .horizontalRow) }
        if musclePair.primary.lowercased().contains("lat") { add(.back, .verticalPull) }
        if musclePair.primary.lowercased().contains("quad") || musclePair.primary.lowercased().contains("leg") { add(.legs, .kneeDominant) }
        if musclePair.primary.lowercased().contains("ham") || musclePair.primary.lowercased().contains("hinge") { add(.legs, .hinge) }
        if musclePair.primary.lowercased().contains("glute") { add(.legs, .gluteIso) }
        if musclePair.primary.lowercased().contains("shoulder") || musclePair.primary.lowercased().contains("delt") { add(.shoulders, .overheadPress) }
        if musclePair.primary.lowercased().contains("bicep") { add(.arms, .bicepsCurl) }
        if musclePair.primary.lowercased().contains("tricep") { add(.arms, .tricepsExtension) }
        if musclePair.primary.lowercased().contains("core") || musclePair.primary.lowercased().contains("abs") { add(.core, .antiExtension) }

        if lower.contains("bench") || lower.contains("press") {
            add(.chest, lower.contains("incline") ? .inclinePress : .horizontalPress)
        }
        if lower.contains("fly") {
            add(.chest, .flyAdduction)
        }
        if lower.contains("dip") {
            add(.chest, .dipPattern)
            add(.arms, .tricepsExtension)
        }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull-down") || lower.contains("pull up") || lower.contains("pull-up") {
            add(.back, lower.contains("pull") ? .verticalPull : .horizontalRow)
        }
        if lower.contains("rear") || lower.contains("face pull") {
            add(.back, .rearDeltUpperBack)
            add(.shoulders, .rearDeltER)
        }
        if lower.contains("squat") || lower.contains("lunge") || lower.contains("leg press") {
            add(.legs, lower.contains("split") || lower.contains("lunge") ? .singleLeg : .kneeDominant)
        }
        if lower.contains("rdl") || lower.contains("deadlift") || lower.contains("hinge") {
            add(.legs, .hinge)
        }
        if lower.contains("calf") {
            add(.legs, .calves)
        }
        if lower.contains("hip thrust") || lower.contains("glute") {
            add(.legs, .gluteIso)
        }
        if lower.contains("ohp") || lower.contains("overhead") || lower.contains("shoulder press") {
            add(.shoulders, .overheadPress)
        }
        if lower.contains("lateral raise") {
            add(.shoulders, .lateralRaise)
        }
        if lower.contains("curl") {
            add(.arms, .bicepsCurl)
        }
        if lower.contains("tricep") || lower.contains("pushdown") || lower.contains("extension") {
            add(.arms, .tricepsExtension)
        }
        if lower.contains("forearm") || lower.contains("grip") {
            add(.arms, .forearmGrip)
        }
        if lower.contains("plank") || lower.contains("ab wheel") {
            add(.core, .antiExtension)
        }
        if lower.contains("pallof") || lower.contains("rotation") {
            add(.core, .antiRotation)
        }
        if lower.contains("crunch") || lower.contains("situp") || lower.contains("sit-up") || lower.contains("leg raise") {
            add(.core, .flexion)
        }
        if lower.contains("carry") || lower.contains("farmer") {
            add(.core, .carry)
        }
        if buckets.isEmpty {
            buckets.append(.core)
        }
        return (buckets, tags)
    }

    private static func scoreForBucket(bucket: MuscleGroup, hardSets: Int, days: Int, covered: Set<MovementTag>, range: StatsLens) -> (Int, [MovementTag], [String], [String]) {
        let targetTags = tagsForBucket(bucket)
        let missingTags = targetTags.filter { !covered.contains($0) }

        let coverageScore = Int((5.0 * Double(covered.count) / Double(max(1, targetTags.count))).rounded())
        let freqScore: Int
        switch range {
        case .week:
            freqScore = days >= 2 ? 2 : (days == 1 ? 1 : 0)
        case .month:
            if days >= 6 { freqScore = 2 }
            else if days >= 3 { freqScore = 1 }
            else { freqScore = 0 }
        case .all:
            if days >= 8 { freqScore = 2 }
            else if days >= 3 { freqScore = 1 }
            else { freqScore = 0 }
        }

        let targets = targetSets(for: bucket)
        let scaledTargetMin: Double
        switch range {
        case .week:
            scaledTargetMin = Double(targets.min)
        case .month:
            scaledTargetMin = Double(targets.min) * (30.0 / 7.0)
        case .all:
            scaledTargetMin = Double(targets.min) * max(1.0, Double(days) / 7.0)
        }
        let doseScore: Int
        if Double(hardSets) >= scaledTargetMin {
            doseScore = 2
        } else if Double(hardSets) >= scaledTargetMin * 0.5 {
            doseScore = 1
        } else {
            doseScore = 0
        }

        let penalty: Int
        if covered.count <= 1 {
            penalty = -2
        } else if covered.count == 2 && targetTags.count >= 4 {
            penalty = -1
        } else {
            penalty = 0
        }

        let rawScore = coverageScore + freqScore + doseScore + penalty
        let finalScore = max(0, min(10, rawScore))

        var reasons: [String] = []
        if range == .all {
            reasons.append("Over all time you trained \(bucket.rawValue) on \(days) days.")
        } else {
            reasons.append("You trained \(bucket.rawValue) on \(days) day(s) this \(range.rawValue.lowercased()).")
        }
        reasons.append("Logged \(hardSets) hard sets for \(bucket.rawValue).")
        if !missingTags.isEmpty {
            let missingNames = missingTags.map { $0.displayName }.joined(separator: ", ")
            reasons.append("Missing movement patterns: \(missingNames).")
        }
        if penalty < 0 {
            reasons.append("Variety penalty applied — expand beyond one pattern.")
        }

        let suggestions = suggestionLines(for: missingTags, bucket: bucket)

        return (finalScore, missingTags, reasons, suggestions)
    }

    private static func tagsForBucket(_ bucket: MuscleGroup) -> [MovementTag] {
        switch bucket {
        case .chest:
            return [.horizontalPress, .inclinePress, .flyAdduction, .dipPattern]
        case .back:
            return [.verticalPull, .horizontalRow, .rearDeltUpperBack, .scapControl]
        case .legs:
            return [.kneeDominant, .hinge, .singleLeg, .calves, .gluteIso]
        case .shoulders:
            return [.overheadPress, .lateralRaise, .rearDeltER]
        case .arms:
            return [.bicepsCurl, .tricepsExtension, .forearmGrip]
        case .core:
            return [.antiExtension, .antiRotation, .flexion, .carry]
        }
    }

    private static func targetSets(for bucket: MuscleGroup) -> (min: Int, max: Int) {
        switch bucket {
        case .chest, .back, .legs:
            return (8, 14)
        case .shoulders, .arms, .core:
            return (6, 12)
        }
    }

    private static func suggestionLines(for missing: [MovementTag], bucket: MuscleGroup) -> [String] {
        guard !missing.isEmpty else {
            return ["Maintain coverage with 1–2 movements per pattern."]
        }
        var lines: [String] = []
        for tag in missing.prefix(3) {
            lines.append(suggestion(for: tag, bucket: bucket))
        }
        return lines
    }

    private static func suggestion(for tag: MovementTag, bucket: MuscleGroup) -> String {
        switch tag {
        case .horizontalPress:
            return "Add a horizontal press (e.g., bench press) 3x8."
        case .inclinePress:
            return "Add incline dumbbell press 3x10 for upper chest."
        case .flyAdduction:
            return "Add cable or pec deck fly 3x12 to round out chest."
        case .dipPattern:
            return "Add dips or assisted dips 3x8 for chest/triceps."
        case .verticalPull:
            return "Add pull-ups or lat pulldowns 3x8 for lats."
        case .horizontalRow:
            return "Add a row variation 3x10 to balance pulling volume."
        case .rearDeltUpperBack:
            return "Add face pulls or rear delt fly 3x12 for upper back."
        case .scapControl:
            return "Add scapular control work (e.g., band pull-aparts)."
        case .kneeDominant:
            return "Add a squat/leg press pattern 3–4 sets."
        case .hinge:
            return "Add RDL or deadlift 3x8 to hit hinge pattern."
        case .singleLeg:
            return "Add split squats or lunges 3x10 each leg."
        case .calves:
            return "Add calf raises 3x12–15 to cover calves."
        case .gluteIso:
            return "Add hip thrusts or glute bridges 3x10."
        case .overheadPress:
            return "Add overhead press 3x8 for shoulders."
        case .lateralRaise:
            return "Add lateral raises 3x12 for side delts."
        case .rearDeltER:
            return "Add rear delt fly/face pulls 3x12."
        case .bicepsCurl:
            return "Add curls 3x10–12 for biceps."
        case .tricepsExtension:
            return "Add tricep pushdowns or extensions 3x10."
        case .forearmGrip:
            return "Add farmer carries or grip work 3 sets."
        case .antiExtension:
            return "Add planks/ab wheel 3 sets to train anti-extension."
        case .antiRotation:
            return "Add pallof presses 3x10 to train anti-rotation."
        case .flexion:
            return "Add crunch or hanging knee raise 3x12 for flexion."
        case .carry:
            return "Add loaded carries 3 sets to build core stability."
        }
    }
}

private extension MovementTag {
    var displayName: String {
        switch self {
        case .horizontalPress: return "Horizontal press"
        case .inclinePress: return "Incline press"
        case .flyAdduction: return "Fly/adduction"
        case .dipPattern: return "Dip pattern"
        case .verticalPull: return "Vertical pull"
        case .horizontalRow: return "Horizontal row"
        case .rearDeltUpperBack: return "Rear delt / upper back"
        case .scapControl: return "Scap control"
        case .kneeDominant: return "Knee-dominant"
        case .hinge: return "Hinge"
        case .singleLeg: return "Single-leg"
        case .calves: return "Calves"
        case .gluteIso: return "Glute iso"
        case .overheadPress: return "Overhead press"
        case .lateralRaise: return "Lateral raise"
        case .rearDeltER: return "Rear delt / ER"
        case .bicepsCurl: return "Biceps curl"
        case .tricepsExtension: return "Triceps extension"
        case .forearmGrip: return "Forearm/grip"
        case .antiExtension: return "Anti-extension"
        case .antiRotation: return "Anti-rotation"
        case .flexion: return "Flexion"
        case .carry: return "Carry"
        }
    }
}
