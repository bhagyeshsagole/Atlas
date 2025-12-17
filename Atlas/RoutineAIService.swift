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
                let workouts = fallbackParse(rawText: generatedList)
                guard !workouts.isEmpty else {
                    throw RoutineAIError.openAIRequestFailed(status: nil, message: "Empty OpenAI response.")
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

        do {
            #if DEBUG
            print("[AI] Using OpenAI model: \(OpenAIConfig.model)")
            #endif
            return try await OpenAIChatClient.generateWorkoutListString(requestText: request, routineTitleHint: routineTitleHint)
        } catch let error as OpenAIError {
            throw RoutineAIError.openAIRequestFailed(status: error.statusCode, message: error.message)
        } catch {
            throw RoutineAIError.openAIRequestFailed(status: nil, message: error.localizedDescription)
        }
    }
}
