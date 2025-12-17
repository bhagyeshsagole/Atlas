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
    /// Parses raw workout input using OpenAI when available, otherwise falls back to local heuristics.
    /// Change impact: Adjust to tweak when the app relies on AI versus deterministic parsing.
    static func parseWorkouts(from rawText: String, routineTitleHint: String? = nil) async -> [ParsedWorkout] {
        let trimmedInput = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        print("[AI] Input: \(trimmedInput)")
        #endif

        guard !trimmedInput.isEmpty else { return [] }

        if isLikelyWorkoutRequest(trimmedInput) {
            #if DEBUG
            print("[AI] Request mode detected")
            #endif
            let generatedList = await generateWorkoutListString(fromRequest: trimmedInput, routineTitleHint: routineTitleHint)
            #if DEBUG
            print("[AI] Generated workout list string: \(generatedList)")
            #endif
            let workouts = fallbackParse(rawText: generatedList)
            logParsed(workouts)
            return workouts
        } else {
            #if DEBUG
            print("[AI] Explicit list mode detected")
            #endif
        }

        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            #if DEBUG
            print("[AI] Missing API key — using fallback")
            #endif
            let workouts = fallbackParse(rawText: trimmedInput)
            logParsed(workouts)
            return workouts
        }

        do {
            #if DEBUG
            print("[AI] Using OpenAI model: \(OpenAIConfig.model)")
            #endif
            let output = try await OpenAIChatClient.parseRoutineWorkouts(rawText: trimmedInput)
            let mapped = output.workouts.map { workout in
                ParsedWorkout(
                    name: workout.name,
                    wtsText: workout.wtsText,
                    repsText: workout.repsText
                )
            }
            if mapped.isEmpty {
                #if DEBUG
                print("[AI] Using fallback parser (reason: empty OpenAI parse)")
                #endif
                let fallback = fallbackParse(rawText: trimmedInput)
                logParsed(fallback)
                return fallback
            }
            logParsed(mapped)
            return mapped
        } catch {
            #if DEBUG
            print("[AI] OpenAI failed (\(error)) — using fallback")
            #endif
            let fallback = fallbackParse(rawText: trimmedInput)
            logParsed(fallback)
            return fallback
        }
    }

    /// VISUAL TWEAK: Change splitting/regex rules here to reshape fallback parsing when AI is unavailable.
    private static func fallbackParse(rawText: String) -> [ParsedWorkout] {
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

        if workouts.isEmpty {
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
        let keywords = ["perfect", "best", "build", "routine", "day", "workout", "pull", "push", "legs"]
        let containsKeyword = keywords.contains { text.contains($0) }
        return !hasDigits || !hasSetsMarker || containsKeyword
    }

    /// Generates a workout list using OpenAI when possible, otherwise uses template-driven fallbacks.
    /// Change impact: Edit to reshape AI prompt wording or offline generation behavior.
    static func generateWorkoutListString(fromRequest request: String, routineTitleHint: String?) async -> String {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            #if DEBUG
            print("[AI] Missing API key — using fallback")
            #endif
            return fallbackGeneratedList(for: request)
        }

        do {
            #if DEBUG
            print("[AI] Using OpenAI model: \(OpenAIConfig.model)")
            #endif
            return try await OpenAIChatClient.generateWorkoutListString(requestText: request, routineTitleHint: routineTitleHint)
        } catch {
            #if DEBUG
            print("[AI] OpenAI failed (\(error)) — using fallback")
            #endif
            return fallbackGeneratedList(for: request)
        }
    }

    /// Provides a deterministic workout list template when OpenAI is unavailable.
    /// Change impact: Edit to adjust the default exercises returned without network access or credentials.
    private static func fallbackGeneratedList(for request: String) -> String {
        let text = request.lowercased()
        if text.contains("pull") {
            return "Lat Pulldown x 3 10-12 and Seated Cable Row x 3 10-12 and Chest Supported Row x 3 10-12 and Face Pull x 3 12-15 and Reverse Fly x 3 12-15 and Dumbbell Curl x 3 10-12 and Hammer Curl x 3 10-12"
        } else if text.contains("push") {
            return "Incline Dumbbell Press x 3 8-12 and Flat Bench Press x 3 8-12 and Seated Shoulder Press x 3 10-12 and Lateral Raise x 3 12-15 and Cable Fly x 3 12-15 and Triceps Rope Pushdown x 3 10-12 and Overhead Triceps Extension x 3 10-12"
        } else if text.contains("legs") {
            return "Back Squat x 4 8-10 and Romanian Deadlift x 3 8-12 and Leg Press x 3 12-15 and Walking Lunge x 3 12-15 and Leg Curl x 3 12-15 and Leg Extension x 3 12-15 and Calf Raise x 4 12-15"
        } else {
            return "Pull Up x 3 8-12 and Dumbbell Bench Press x 3 8-12 and Bent Over Row x 3 10-12 and Shoulder Press x 3 10-12 and Lateral Raise x 3 12-15 and Barbell Curl x 3 10-12 and Triceps Pushdown x 3 10-12"
        }
    }
}
