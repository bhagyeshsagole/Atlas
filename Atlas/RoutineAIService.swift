//
//  RoutineAIService.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
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
}

struct RoutineAIService {
    enum RoutineAIError: Error {
        case missingAPIKey
        case openAIRequestFailed(status: Int?, message: String)
    }

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
                let generatedList = try await generateWorkoutListString(fromRequest: trimmedInput, routineTitleHint: routineTitleHint)
                #if DEBUG
                print("[AI] Generated workout list string: \(generatedList)")
                #endif
                let workouts = fallbackParse(rawText: generatedList, allowFallbackPlaceholder: false)
                guard !workouts.isEmpty else {
                    throw RoutineAIError.openAIRequestFailed(status: nil, message: "AI returned an invalid format. Try rephrasing or specify equipment limits.")
                }
                logParsed(workouts)
                return workouts
            } catch let error as RoutineAIError {
                throw error
            } catch {
                throw RoutineAIError.openAIRequestFailed(status: nil, message: error.localizedDescription)
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
            let repsText = repsMatch.map { String(piece[$0]).replacingOccurrences(of: " ", with: "") } ?? "reps"

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
                    repsText: "reps"
                )
            ]
        }
        return workouts
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

    /// Detects whether the input is a request for a program versus an explicit list of exercises.
    /// Change impact: Tuning the keywords changes when the app calls AI generation versus parsing user lists directly.
    static func isLikelyWorkoutRequest(_ rawText: String) -> Bool {
        let text = rawText.lowercased()
        let hasDigits = rawText.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSetsMarker = text.contains("x") || text.contains("×")
        let keywords = ["perfect", "best", "build", "routine", "day", "workout", "pull", "push", "leg", "legs", "lower", "lower body"]
        let containsKeyword = keywords.contains { text.contains($0) }
        return !hasDigits || !hasSetsMarker || containsKeyword
    }

    /// Generates a workout list using OpenAI only; errors bubble to caller.
    /// Change impact: Adjust prompt wording or model to tune AI behavior.
    static func generateWorkoutListString(fromRequest request: String, routineTitleHint: String?) async throws -> String {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            throw RoutineAIError.missingAPIKey
        }

        let constraints = extractConstraints(from: request)
        let focus = detectFocus(in: request, preferredSplit: constraints.preferredSplit)
        let ruleSummary = minimumRuleSummary(for: focus)
        var attempt = 0
        var lastError: String?
        var requireExactFormatReminder = false
        var lastFailureWasFormat = false

        while attempt < 2 {
            do {
                #if DEBUG
                print("[AI] Using OpenAI model: \(OpenAIConfig.model)")
                #endif
                let correctiveNote = lastError.map { "Your last output did not meet the minimums. Regenerate meeting: \($0)" }
                let response = try await OpenAIChatClient.generateWorkoutListString(
                    requestText: request,
                    routineTitleHint: routineTitleHint,
                    constraints: constraints,
                    correctiveNote: correctiveNote,
                    forceExactFormatReminder: requireExactFormatReminder
                )
                let normalizedList = normalizeWorkoutList(response.workoutList)
                let exercises = parseExercises(from: normalizedList)
                if !exercises.isEmpty && validate(exercises: exercises, for: focus) {
                    return normalizedList
                }

                lastFailureWasFormat = exercises.isEmpty
                if exercises.isEmpty {
                    lastError = "Return JSON with workoutList in EXACT format. No bullets. No commas."
                    requireExactFormatReminder = true
                } else {
                    lastError = ruleSummary
                }
            } catch let error as OpenAIError {
                throw RoutineAIError.openAIRequestFailed(status: error.statusCode, message: error.message)
            } catch {
                throw RoutineAIError.openAIRequestFailed(status: nil, message: error.localizedDescription)
            }
            attempt += 1
        }

        if lastFailureWasFormat {
            throw RoutineAIError.openAIRequestFailed(status: nil, message: "AI returned an invalid format. Try rephrasing or specify equipment limits.")
        } else {
            throw RoutineAIError.openAIRequestFailed(status: nil, message: "AI output didn’t meet routine requirements. Try again.")
        }
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

    private static func detectFocus(in request: String, preferredSplit: RoutineConstraints.PreferredSplit? = nil) -> Focus {
        let text = request.lowercased()
        func containsAny(_ keywords: [String]) -> Bool {
            keywords.contains { text.contains($0) }
        }

        if let preferredSplit {
            switch preferredSplit {
            case .push: return .push
            case .pull: return .pull
            case .legs: return .legs
            }
        }

        if containsAny(["pull"]) { return .pull }
        if containsAny(["push"]) { return .push }
        if containsAny(["full body", "full-body", "total body"]) { return .fullBody }
        if containsAny(["shoulder", "delt"]) { return .shoulders }
        if containsAny(["chest", "pec"]) { return .chest }
        if containsAny(["back", "lat", "lats"]) { return .back }
        if containsAny(["leg", "quad", "ham", "glute"]) { return .legs }
        if containsAny(["bicep", "biceps"]) { return .biceps }
        if containsAny(["tricep", "triceps"]) { return .triceps }
        if containsAny(["arm", "arms"]) { return .arms }
        return .generic
    }

    private enum Focus {
        case shoulders, chest, back, legs, biceps, triceps, arms, pull, push, fullBody, generic
    }

    private static func minimumRuleSummary(for focus: Focus) -> String {
        switch focus {
        case .shoulders: return "Shoulders: >= 3 movements (overhead press + lateral raise + rear delt)."
        case .chest: return "Chest: >= 3 movements (horizontal press + incline press + fly/pec isolation)."
        case .back: return "Back: >= 4 movements with vertical pull + horizontal row + rear delt."
        case .legs: return "Legs: >= 5 movements (squat pattern + hinge pattern + quad iso + hamstring iso + calves/core)."
        case .biceps: return "Biceps: >= 3 movements."
        case .triceps: return "Triceps: >= 3 movements."
        case .arms: return "Arms day: 6–8 movements with Biceps >= 3 and Triceps >= 3."
        case .pull: return "Pull day: 6–8 total, Back >= 4, Biceps >= 2, include rear delt."
        case .push: return "Push day: 6–8 total, Chest >= 3, Shoulders >= 2, Triceps 1–2."
        case .fullBody: return "Full body: 7–10 total covering squat + hinge + push + pull + core."
        case .generic: return "6–10 balanced exercises with compounds first."
        }
    }

    private static func parseExercises(from generated: String) -> [String] {
        generated
            .components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeWorkoutList(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "&", with: "and")

        let separators = CharacterSet(charactersIn: ",;\n")
        normalized = normalized
            .components(separatedBy: separators)
            .joined(separator: " and ")

        normalized = normalized.replacingOccurrences(of: #"(\d+)\s*x\s*(\d+)"#, with: "$1 x $2", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"x\s*(\d+)"#, with: " x $1 ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"(\d+)x"#, with: "$1 x ", options: .regularExpression)

        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }
        while normalized.contains(" and  and ") {
            normalized = normalized.replacingOccurrences(of: " and  and ", with: " and ")
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validate(exercises: [String], for focus: Focus) -> Bool {
        let totals = countByCategory(exercises: exercises)
        let total = exercises.count

        switch focus {
        case .shoulders:
            return totals.shoulders >= 3
        case .chest:
            return totals.chest >= 3
        case .back:
            return totals.back >= 4
        case .legs:
            return totals.legs >= 5
        case .biceps:
            return totals.biceps >= 3
        case .triceps:
            return totals.triceps >= 3
        case .arms:
            return (6...8).contains(total) && totals.biceps >= 3 && totals.triceps >= 3
        case .pull:
            return (6...8).contains(total) && totals.back >= 4 && totals.biceps >= 2 && totals.rearDelts >= 1
        case .push:
            return (6...8).contains(total) && totals.chest >= 3 && totals.shoulders >= 2 && totals.triceps >= 1
        case .fullBody:
            return (7...10).contains(total)
                && totals.squatPatterns >= 1
                && totals.hingePatterns >= 1
                && totals.pushPatterns >= 1
                && totals.pullPatterns >= 1
                && totals.core >= 1
        case .generic:
            return (6...10).contains(total)
        }
    }

    private struct CategoryTotals {
        var shoulders = 0
        var chest = 0
        var back = 0
        var legs = 0
        var biceps = 0
        var triceps = 0
        var rearDelts = 0
        var squatPatterns = 0
        var hingePatterns = 0
        var pushPatterns = 0
        var pullPatterns = 0
        var core = 0
    }

    private static func countByCategory(exercises: [String]) -> CategoryTotals {
        var totals = CategoryTotals()
        for exercise in exercises {
            let name = exercise.lowercased()
            func containsAny(_ keywords: [String]) -> Bool {
                keywords.contains { name.contains($0) }
            }

            let isRearDelt = containsAny(["rear delt", "face pull", "reverse fly", "reverse pec deck", "reverse-pec deck", "rear raise"])
            let isShoulderPress = containsAny(["overhead press", "ohp", "shoulder press", "military press", "arnold press", "push press"])
            let isLateralRaise = containsAny(["lateral raise", "side raise", "delt raise"])
            let isShoulder = containsAny(["shoulder", "delt"]) || isShoulderPress || isLateralRaise || isRearDelt
            if isShoulder { totals.shoulders += 1 }

            let isPushUp = containsAny(["push-up", "push up"])
            let isBenchStyle = containsAny([
                "bench press",
                "flat bench",
                "incline press",
                "incline bench",
                "decline press",
                "dumbbell press",
                "machine press",
                "chest press",
                "db bench",
                "barbell bench"
            ]) || (name.contains("press") && containsAny(["bench", "incline", "flat"]) && !name.contains("leg press"))
            let isFly = containsAny(["fly", "pec deck", "pec-deck", "cable crossover", "crossover"])
            let isChest = containsAny(["chest", "pec"]) || isBenchStyle || isFly || isPushUp
            if isChest { totals.chest += 1 }

            let isRow = containsAny(["row", "t-bar", "t bar", "pendlay", "seal row"])
            let isVerticalPull = containsAny(["pulldown", "pull-down", "pull up", "pull-up", "chin up", "chin-up", "neutral grip pullup", "neutral-grip pullup"])
            let isBack = containsAny(["back", "lat", "lats", "trap"]) || isRow || isVerticalPull || isRearDelt
            if isBack { totals.back += 1 }

            let isSquat = containsAny(["squat", "split squat", "front squat", "back squat", "hack squat", "leg press", "step-up", "step up", "lunge", "bulgarian", "pistol"])
            let isHinge = containsAny(["deadlift", "romanian", "rdl", "good morning", "good-morning", "hip hinge", "hip thrust", "hip thrusts", "hip extension", "glute bridge", "kb swing", "kettlebell swing", "back extension"])
            let isQuadIso = containsAny(["leg extension", "quad"])
            let isHamIso = containsAny(["leg curl", "hamstring curl", "hamstring-curl", "hamstring"])
            let isCalf = containsAny(["calf"])
            let isGlute = containsAny(["glute"])
            let isLeg = isSquat || isHinge || isQuadIso || isHamIso || isCalf || isGlute || containsAny(["leg", "ham", "quad", "glute"])
            if isLeg { totals.legs += 1 }
            if isSquat { totals.squatPatterns += 1 }
            if isHinge { totals.hingePatterns += 1 }

            let mentionsLegCurl = containsAny(["leg curl", "hamstring curl", "hamstring-curl"])
            let isBicepsCurl = name.contains("curl") && !mentionsLegCurl && !containsAny(["hamstring"])
            let isChinUp = containsAny(["chin up", "chin-up"])
            let isBiceps = containsAny(["bicep", "biceps", "preacher", "hammer curl", "drag curl"]) || isBicepsCurl || isChinUp
            if isBiceps { totals.biceps += 1 }

            let isTricepsExtension = containsAny(["tricep", "triceps", "skullcrusher", "skull crusher", "french press", "pressdown", "pushdown", "overhead extension", "overhead tricep", "overhead triceps"])
            let isDip = containsAny(["dip", "dips"])
            let isCloseGrip = containsAny(["close-grip", "close grip"])
            let isTriceps = isTricepsExtension || isDip || isCloseGrip
            if isTriceps { totals.triceps += 1 }

            let isCore = containsAny(["plank", "crunch", "sit-up", "sit up", "dead bug", "hollow", "leg raise", "knee raise", "ab wheel", "rollout", "pallof", "wood chop", "woodchop", "carry", "farmer"])
            if isCore { totals.core += 1 }

            let isPressing = isBenchStyle || isPushUp || isShoulderPress || isDip || isCloseGrip
            if isPressing { totals.pushPatterns += 1 }

            if isRow || isVerticalPull || isRearDelt {
                totals.pullPatterns += 1
            }

            if isRearDelt { totals.rearDelts += 1 }
        }
        return totals
    }
}
