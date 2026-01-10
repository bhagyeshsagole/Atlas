//
//  RoutineAIService.swift
//  Atlas
//
//  What this file is:
//  - High-level AI pipeline that parses user workout requests, generates/repairs routines, and fetches coaching/summary text.
//
//  Where it’s used:
//  - Called from routine creation flows and workout screens to turn free-form text into structured workouts and coaching tips.
//
//  Called from:
//  - `CreateRoutineView` (parsing), `ReviewRoutineView` (summary), and `WorkoutSessionView` (coaching + summaries) trigger these APIs.
//
//  Key concepts:
//  - Uses staged calls (generate → repair → parse) to coerce AI output into valid JSON.
//  - Caches exercise coaching by routine/exercise to avoid repeat network calls in a session.
//
//  Safe to change:
//  - Prompt strings or defaults (sets/reps) as long as you handle empty or failed responses gracefully.
//
//  NOT safe to change:
//  - Removing error handling around API key presence; callers rely on predictable fallback errors.
//  - The staged repair pipeline without updating parsing; skipping repair can surface malformed JSON to the UI.
//
//  Common bugs / gotchas:
//  - Forgetting to trim inputs results in empty requests and skipped AI calls.
//  - Changing cache keys can make suggestions stale or re-request too often.
//
//  DEV MAP:
//  - See: DEV_MAP.md → D) AI / OpenAI
//
// FLOW SUMMARY:
// User enters routine text → detect request vs explicit list → if request, call OpenAIChatClient generate → repair JSON → decode to ParsedWorkout → UI saves via RoutineStore; coaching/summaries use similar request/repair/parse cycle.
//

import Foundation

struct ParsedWorkout: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    var wtsText: String
    var repsText: String

    init(id: UUID = UUID(), name: String, wtsText: String = "wts", repsText: String = "reps") {
        self.id = id
        self.name = name
        self.wtsText = wtsText
        self.repsText = repsText
    }

    static func cleanExerciseName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let parts = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

struct RoutineAIService {
    /// DEV MAP: AI pipeline (routine parsing/generation, summaries, coaching) lives here.

    struct ExerciseSuggestion: Hashable {
        var techniqueTips: String
        var thisSessionPlan: String
        var suggestedWeightKg: Double?
        var suggestedReps: String
        var suggestedTag: String
    }

    private struct CoachingCacheKey: Hashable {
        let routineId: UUID?
        let exerciseName: String
        let lastSessionDate: Date?
    }

    private static var coachingCache: [CoachingCacheKey: ExerciseSuggestion] = [:] // Prevent duplicate AI calls within a session for the same exercise context.

    struct RoutineConstraints {
        enum PreferredSplit: String {
            case push, pull, legs
        }

        var atHome: Bool
        var noGym: Bool
        var noDumbbells: Bool
        var noMachines: Bool
        var bodyweightOnly: Bool
        var preferredSplit: PreferredSplit?
    }

    /// VISUAL TWEAK: Change `defaultSets` to adjust auto-fill behavior.
    private static let defaultSets = 3
    /// VISUAL TWEAK: Change `defaultReps` to adjust auto-fill behavior.
    private static let defaultReps = "10-12"
    /// VISUAL TWEAK: Change `minWorkoutCount` to require more/less exercises.
    private static let minWorkoutCount = 5

    /// Generates a concise summary for a routine using OpenAI.
    /// Change impact: Adjust prompt or fallback text to tweak summary style without blocking save.
    static func generateRoutineSummary(routineTitle: String, workouts: [RoutineWorkout]) async throws -> String {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            throw RoutineAIError.missingAPIKey
        }

        #if DEBUG
        print("[AI][SUMMARY] start routine=\(routineTitle)")
        #endif

        do {
            let summary = try await OpenAIChatClient.generateRoutineSummary(
                routineTitle: routineTitle,
                workouts: workouts
            )
            #if DEBUG
            print("[AI][SUMMARY] status=\(summary.status) ms=\(summary.elapsedMs)")
            #endif
            let trimmed = summary.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Summary unavailable. Try again." : trimmed
        } catch let error as OpenAIError {
            throw RoutineAIError.httpStatus(error.statusCode ?? -1, body: nil)
        } catch {
            throw RoutineAIError.requestFailed(underlying: error.localizedDescription)
        }
    }

    /// Generates technique tips and session targets for a specific exercise. Non-blocking: returns fallback text on failure.
    /// Change impact: Adjust prompt or caching key to change how often tips refresh.
    static func generateExerciseCoaching(
        routineTitle: String,
        routineId: UUID?,
        exerciseName: String,
        lastSessionSetsText: String,
        lastSessionDate: Date?,
        preferredUnit: WorkoutUnits
    ) async -> ExerciseSuggestion {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            return defaultSuggestion()
        }

        let cacheKey = CoachingCacheKey(routineId: routineId, exerciseName: exerciseName.lowercased(), lastSessionDate: lastSessionDate)
        if let cached = coachingCache[cacheKey] {
            return cached
        }

        #if DEBUG
        print("[AI][COACH] start exercise=\(exerciseName)")
        #endif

        do {
            let result = try await OpenAIChatClient.generateExerciseCoaching(
                routineTitle: routineTitle,
                exerciseName: exerciseName,
                lastSessionSetsText: lastSessionSetsText,
                preferredUnit: preferredUnit
            )
            let suggestion = result.suggestion
            #if DEBUG
            print("[AI][COACH] status=\(result.status) ms=\(result.elapsedMs)")
            #endif
            coachingCache[cacheKey] = suggestion
            return suggestion
        } catch let error as OpenAIError {
            #if DEBUG
            print("[AI][COACH] error status=\(String(describing: error.statusCode)) message=\(error.message)")
            #endif
            return defaultSuggestion()
        } catch {
            #if DEBUG
            print("[AI][COACH] error message=\(error.localizedDescription)")
            #endif
            return defaultSuggestion()
        }
    }

    private static func defaultSuggestion() -> ExerciseSuggestion {
        ExerciseSuggestion(
            techniqueTips: "Tips unavailable — continue logging.",
            thisSessionPlan: "Follow your usual working sets.",
            suggestedWeightKg: nil,
            suggestedReps: "10-12",
            suggestedTag: "S"
        )
    }

    /// Parses raw workout input using OpenAI for requests or local heuristics for explicit lists.
    /// Change impact: Adjust to tweak when the app relies on AI versus deterministic parsing.
    static func parseWorkouts(from rawText: String, routineTitleHint: String? = nil) async throws -> [ParsedWorkout] {
        let trimmedInput = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("[AI] Input: \(trimmedInput)")
        #endif

        guard !trimmedInput.isEmpty else { return [] }

        if isLikelyWorkoutRequest(trimmedInput) {
            #if DEBUG
            print("[AI] Request mode detected")
            #endif
            do {
                let workouts = try await generateRoutineWorkouts(fromRequest: trimmedInput)
                logParsed(workouts)
                return workouts
            } catch let error as RoutineAIError {
                throw error
            } catch {
                throw RoutineAIError.requestFailed(underlying: error.localizedDescription)
            }
        } else {
            #if DEBUG
            print("[AI] Explicit list mode detected")
            #endif
            let workouts = fallbackParse(rawText: trimmedInput)
            logParsed(workouts)
            return workouts
        }
    }

    /// Stage pipeline: Generate → Repair → Parse → Guarantee.
    private static func generateRoutineWorkouts(fromRequest request: String) async throws -> [ParsedWorkout] {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            throw RoutineAIError.missingAPIKey
        }

        let constraints = extractConstraints(from: request)
        let requestId = makeRequestId()
        var lastRaw: String = ""

        do {
            let generation = try await OpenAIChatClient.generateRoutineFreeform(requestText: request, constraints: constraints, requestId: requestId)
            lastRaw = generation.text

            if let repaired = try? await OpenAIChatClient.repairRoutine(rawText: generation.text, constraints: constraints, requestId: requestId, strict: false).response.workouts,
               let parsed = validateAndConvert(repaired) {
                return parsed
            }

            if let repairedStrict = try? await OpenAIChatClient.repairRoutine(rawText: generation.text, constraints: constraints, requestId: requestId, strict: true).response.workouts,
               let parsed = validateAndConvert(repairedStrict) {
                return parsed
            }
        } catch let error as OpenAIError {
            let bodyString: String? = nil
            throw RoutineAIError.httpStatus(error.statusCode ?? -1, body: bodyString)
        } catch {
            throw RoutineAIError.requestFailed(underlying: error.localizedDescription)
        }

        let salvaged = salvageWorkouts(from: lastRaw, requestId: requestId)
        if !salvaged.isEmpty {
            return salvaged
        }

        throw RoutineAIError.requestFailed(underlying: "Unable to generate routine. Please try again.")
    }

    /// VISUAL TWEAK: Change splitting/regex rules here to reshape fallback parsing when AI is unavailable.
    private static func fallbackParse(rawText: String, allowFallbackPlaceholder: Bool = true) -> [ParsedWorkout] {
        let separators = CharacterSet(charactersIn: ",;\n")
        let normalized = rawText
            .replacingOccurrences(of: "(?i)\\band\\b", with: "|", options: .regularExpression)
            .components(separatedBy: separators)
            .joined(separator: "|")

        let pieces = normalized
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var workouts: [ParsedWorkout] = pieces.map { piece in
            let repsMatch = piece.range(of: #"\d+\s*-\s*\d+"#, options: .regularExpression)
            let repsText = repsMatch.map { String(piece[$0]).replacingOccurrences(of: " ", with: "") } ?? defaultReps

            var namePart = piece
            if let repsMatch {
                namePart.removeSubrange(repsMatch)
            }
            namePart = namePart.replacingOccurrences(of: #"x\s*\d+"#, with: "", options: .regularExpression)
            namePart = namePart.replacingOccurrences(of: #"(?i)sets?"#, with: "", options: .regularExpression)
            namePart = namePart.replacingOccurrences(of: #"(?i)reps?"#, with: "", options: .regularExpression)
            namePart = namePart.replacingOccurrences(of: #"(?i)and"#, with: "", options: .regularExpression)

            let cleanedName = titleCased(namePart.trimmingCharacters(in: .whitespacesAndNewlines))

            return ParsedWorkout(
                name: cleanedName.isEmpty ? "Workout" : cleanedName,
                wtsText: "wts",
                repsText: repsText
            )
        }

        if workouts.isEmpty && allowFallbackPlaceholder {
            workouts = [
                ParsedWorkout(
                    name: titleCased(rawText),
                    wtsText: "wts",
                    repsText: defaultReps
                )
            ]
        }
        return workouts
    }

    private static func validateAndConvert(_ repaired: [RepairedWorkout]) -> [ParsedWorkout]? {
        var parsed: [ParsedWorkout] = repaired.compactMap { item in
            let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            let sets = (item.sets ?? defaultSets)
            guard (1...10).contains(sets) else { return nil }
            let reps = (item.reps?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? defaultReps
            return ParsedWorkout(name: titleCased(trimmedName), wtsText: "wts", repsText: "\(sets)x\(reps)")
        }

        if parsed.count < minWorkoutCount, !parsed.isEmpty {
            // Pad by recycling existing moves to meet minimum without inventing new templates.
            var index = 0
            while parsed.count < minWorkoutCount {
                let base = parsed[index % parsed.count]
                parsed.append(ParsedWorkout(name: base.name + " (Alt)", wtsText: base.wtsText, repsText: base.repsText))
                index += 1
            }
        }

        return parsed.count >= minWorkoutCount ? parsed : nil
    }

    private static func salvageWorkouts(from raw: String, requestId: String) -> [ParsedWorkout] {
        var parsed = fallbackParse(rawText: raw)
        if parsed.isEmpty {
            return []
        }
        parsed = parsed.map {
            ParsedWorkout(name: $0.name, wtsText: "wts", repsText: "\(defaultSets)x\(defaultReps)")
        }
        var index = 0
        while parsed.count < minWorkoutCount {
            let base = parsed[index % parsed.count]
            parsed.append(ParsedWorkout(name: base.name + " (Alt)", wtsText: base.wtsText, repsText: base.repsText))
            index += 1
        }
        #if DEBUG
        print("[AI][\(requestId)] salvage_local=true workouts=\(parsed.count)")
        #endif
        return parsed
    }

    private static func titleCased(_ text: String) -> String {
        text
            .split(separator: " ")
            .map { word in
                word.lowercased().prefix(1).uppercased() + word.lowercased().dropFirst()
            }
            .joined(separator: " ")
    }

    private static func logParsed(_ workouts: [ParsedWorkout]) {
        #if DEBUG
        let names = workouts.map(\.name).joined(separator: ", ")
        print("[AI] Parsed \(workouts.count) workouts: \(names)")
        #endif
    }

    /// DEV MAP: Post-workout summary prompt + JSON schema lives here.
    static func generatePostWorkoutSummary(
        session: WorkoutSession,
        previousSessionsByExercise: [String: ExerciseLog?],
        unitPreference: WorkoutUnits
    ) async -> (payload: PostWorkoutSummaryPayload, rawJSON: String, model: String)? {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            #if DEBUG
            print("[AI][POST] Key present: false model=\(OpenAIConfig.model)")
            #endif
            return fallbackSummary(session: session)
        }

        #if DEBUG
        print("[AI][POST] Key present: true model=\(OpenAIConfig.model)")
        print("[AI][POST] session=\(session.id) model=\(OpenAIConfig.model) start")
        #endif

        do {
            let local = makeLocalSummaryContext(session: session, previousSessionsByExercise: previousSessionsByExercise, unitPreference: unitPreference)
            let result = try await OpenAIChatClient.generatePostWorkoutSummary(context: local)
            #if DEBUG
        print("[AI][POST] status=\(result.status) ms=\(result.elapsedMs)")
        #endif
        if let payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: Data(result.text.utf8)) {
            #if DEBUG
            let ratingLog = payload.rating ?? 0
            print("[AI][POST] parsed ok rating=\(ratingLog)")
            #endif
            return (payload, result.text, OpenAIConfig.model)
        }

        if let repaired = try? await OpenAIChatClient.repairPostWorkoutSummary(rawText: result.text),
           let payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: Data(repaired.text.utf8)) {
            #if DEBUG
            let ratingLog = payload.rating ?? 0
            print("[AI][POST][REPAIR] status=\(repaired.status) ms=\(repaired.elapsedMs) rating=\(ratingLog)")
            #endif
            return (payload, repaired.text, OpenAIConfig.model)
        }
        } catch let error as OpenAIError {
            #if DEBUG
            print("[AI][POST] error status=\(String(describing: error.statusCode)) message=\(error.message)")
            #endif
            return fallbackSummary(session: session)
        } catch {
            #if DEBUG
            print("[AI][POST] error message=\(error.localizedDescription)")
            #endif
            return fallbackSummary(session: session)
        }

        return fallbackSummary(session: session)
    }

    private static func fallbackSummary(session: WorkoutSession) -> (payload: PostWorkoutSummaryPayload, rawJSON: String, model: String)? {
        let dateLine = makeFormatter().string(from: session.startedAt)
        let payload = PostWorkoutSummaryPayload(
            sessionDate: dateLine,
            rating: 7.0,
            insight: "Fallback summary. Add more history for richer insights.",
            prs: [],
            improvements: [
                "Match last best sets and focus on consistent reps.",
                "Add one support move if time allows."
            ],
            tldr: nil,
            sections: nil
        )
        if let data = try? JSONEncoder().encode(payload), let raw = String(data: data, encoding: .utf8) {
            return (payload, raw, OpenAIConfig.model)
        }
        return nil
    }

    struct PostSummaryContext {
        let sessionDate: String
        let routineTitle: String
        let durationMinutes: Int
        let totals: (sets: Int, reps: Int, volumeKg: Double, volumeLb: Double)
        let exercises: [ExerciseContext]
        let unitPreference: WorkoutUnits
    }

    struct ExerciseContext {
        let name: String
        let muscles: (String, String)
        let sets: [SetLog]
        let previous: ExerciseLog?
    }

    private static func makeLocalSummaryContext(
        session: WorkoutSession,
        previousSessionsByExercise: [String: ExerciseLog?],
        unitPreference: WorkoutUnits
    ) -> PostSummaryContext {
        let formatter = makeFormatter()
        let dateLine = formatter.string(from: session.startedAt)
        let durationSeconds = session.durationSeconds ?? Int((session.endedAt ?? Date()).timeIntervalSince(session.startedAt))
        let durationMinutes = max(1, durationSeconds / 60)
        let totalSets = totalSets(session: session)
        let totalReps = totalReps(session: session)
        let volumeKg = computeVolumeKg(session: session)
        let volumeLb = volumeKg * WorkoutSessionFormatter.kgToLb

        let exercises: [ExerciseContext] = session.exercises.map { ex in
            let prev = previousSessionsByExercise[ex.name.lowercased()] ?? nil
            return ExerciseContext(
                name: ex.name,
                muscles: ExerciseMuscleMap.muscles(for: ex.name),
                sets: ex.sets,
                previous: prev ?? nil
            )
        }

        return PostSummaryContext(
            sessionDate: dateLine,
            routineTitle: session.routineTitle,
            durationMinutes: durationMinutes,
            totals: (totalSets, totalReps, volumeKg, volumeLb),
            exercises: exercises,
            unitPreference: unitPreference
        )
    }

    private static func totalSets(session: WorkoutSession) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    private static func totalReps(session: WorkoutSession) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.reps } }
    }

    private static func computeVolumeKg(session: WorkoutSession) -> Double {
        session.exercises.flatMap(\.sets).reduce(0) { partial, set in
            guard let weight = set.weightKg else { return partial }
            return partial + weight * Double(set.reps)
        }
    }

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL dd, yyyy (EEEE)"
        return formatter
    }

    /// Detects whether the input is a request for a program versus an explicit list of exercises.
    /// Change impact: Tuning the keywords changes when the app calls AI generation versus parsing user lists directly.
    static func isLikelyWorkoutRequest(_ rawText: String) -> Bool {
        let text = rawText.lowercased()
        let hasDigits = rawText.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSetsMarker = text.contains("x") || text.contains("×")
        let keywords = ["perfect", "best", "build", "routine", "day", "workout", "pull", "push", "leg", "legs", "lower", "lower body", "forearm", "forearms", "back", "chest", "shoulder"]
        let containsKeyword = keywords.contains { text.contains($0) }
        return !hasDigits || !hasSetsMarker || containsKeyword
    }

    /// VISUAL TWEAK: Add/remove keywords in `extractConstraints` to match how you naturally type.
    static func extractConstraints(from text: String) -> RoutineConstraints {
        let lower = text.lowercased()
        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { lower.contains($0) }
        }

        let atHome = containsAny(["home", "at home", "home workout", "home-based", "home based", "home gym"])
        let noGym = containsAny(["no gym", "without gym"])
        let noDumbbells = containsAny(["no dumbbell", "no dumbbells"])
        let noMachines = containsAny(["no machine", "no machines", "no cables", "no cable"])
        let bodyweightOnly = containsAny(["no equipment", "bodyweight only", "body weight only"])

        var preferredSplit: RoutineConstraints.PreferredSplit?
        if containsAny(["push"]) { preferredSplit = .push }
        else if containsAny(["pull"]) { preferredSplit = .pull }
        else if containsAny(["leg", "legs"]) { preferredSplit = .legs }

        return RoutineConstraints(
            atHome: atHome,
            noGym: noGym,
            noDumbbells: noDumbbells,
            noMachines: noMachines,
            bodyweightOnly: bodyweightOnly,
            preferredSplit: preferredSplit
        )
    }

    private static func makeRequestId() -> String {
        String(UUID().uuidString.prefix(4)).uppercased()
    }
}

extension RoutineAIService {
    static func cleanExerciseName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let parts = trimmed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
