//
//  RoutineAIService.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//
//  Update: Rebuilt AI pipeline (generate → repair → parse) with auto-repair and local salvage to avoid user-facing format errors.

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
            throw RoutineAIError.openAIRequestFailed(status: error.statusCode, message: error.message)
        } catch {
            throw RoutineAIError.openAIRequestFailed(status: nil, message: error.localizedDescription)
        }
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
            throw RoutineAIError.openAIRequestFailed(status: error.statusCode, message: error.message)
        } catch {
            throw RoutineAIError.openAIRequestFailed(status: nil, message: error.localizedDescription)
        }

        let salvaged = salvageWorkouts(from: lastRaw, requestId: requestId)
        if !salvaged.isEmpty {
            return salvaged
        }

        throw RoutineAIError.openAIRequestFailed(status: nil, message: "Unable to generate routine. Please try again.")
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
