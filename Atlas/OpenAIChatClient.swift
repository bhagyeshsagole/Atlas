//
//  OpenAIChatClient.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//

import Foundation

struct RoutineParseOutput: Codable {
    let workouts: [RoutineParseWorkout]
}

struct RoutineParseWorkout: Codable {
    let name: String
    let wtsText: String
    let repsText: String
}

struct WorkoutListResponse: Codable {
    let workoutList: String
    let notes: String?
}

struct OpenAIError: Error {
    let statusCode: Int?
    let message: String
}

struct OpenAIChatClient {
    /// Sends a structured parsing request to OpenAI and maps the response to workout data.
    /// Change impact: Edit to reshape the parsing prompt, temperature, or JSON decoding strategy.
    static func parseRoutineWorkouts(rawText: String) async throws -> RoutineParseOutput {
        let messages: [ChatMessage] = [
            .init(role: "developer", content: Self.prompt),
            .init(role: "user", content: rawText)
        ]
        let request = try buildRequest(messages: messages, temperature: 0.2, responseFormat: ResponseFormat(type: "json_object"))
        let (data, _) = try await perform(request: request)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: nil, message: "No content returned from OpenAI.")
        }

        #if DEBUG
        print("[AI] OpenAI response received.")
        #endif

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw OpenAIError(statusCode: nil, message: "Unable to encode model response.")
        }

        do {
            return try JSONDecoder().decode(RoutineParseOutput.self, from: jsonData)
        } catch {
            throw OpenAIError(statusCode: nil, message: "Failed to decode routine JSON: \(error.localizedDescription)")
        }
    }

    /// Generates a workout list string via OpenAI with the configured prompt and temperature.
    /// Change impact: Modify to tune creativity, prompt wording, or formatting expectations.
    static func generateWorkoutListString(
        requestText: String,
        routineTitleHint: String?,
        constraints: RoutineAIService.RoutineConstraints,
        correctiveNote: String? = nil,
        forceExactFormatReminder: Bool = false
    ) async throws -> WorkoutListResponse {
        var userContent = "Request: \(requestText)"
        userContent += "\nRoutineTitleHint: \(routineTitleHint ?? "")"
        userContent += "\nConstraints: atHome=\(constraints.atHome), noGym=\(constraints.noGym), noDumbbells=\(constraints.noDumbbells), noMachines=\(constraints.noMachines), bodyweightOnly=\(constraints.bodyweightOnly), preferredSplit=\(constraints.preferredSplit?.rawValue ?? "nil")"
        if let correctiveNote {
            userContent += "\nCorrection: \(correctiveNote)"
        }
        if forceExactFormatReminder {
            userContent += "\nReturn JSON with workoutList in EXACT format. No bullets. No commas."
        }

        let messages: [ChatMessage] = [
            .init(role: "developer", content: generatorPrompt),
            .init(role: "user", content: userContent)
        ]
        let request = try buildRequest(messages: messages, temperature: 0.25, responseFormat: ResponseFormat(type: "json_object"))
        let (data, _) = try await perform(request: request)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: nil, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw OpenAIError(statusCode: nil, message: "Unable to encode model response.")
        }

        do {
            return try JSONDecoder().decode(WorkoutListResponse.self, from: jsonData)
        } catch {
            throw OpenAIError(statusCode: nil, message: "Failed to decode workout list JSON: \(error.localizedDescription)")
        }
    }

    /// VISUAL TWEAK: Adjust fence stripping here to tolerate different model formatting.
    private static func stripCodeFences(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        if let firstFence = trimmed.range(of: "```"),
           let lastFence = trimmed.range(of: "```", options: .backwards),
           firstFence.lowerBound != lastFence.lowerBound {
            let inner = trimmed[firstFence.upperBound..<lastFence.lowerBound]
            return String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static let prompt = """
You are a routine parser. Convert the user's text into JSON.

Rules:
- Output MUST be valid JSON only.
- Extract each exercise/workout as an item.
- `name` must be a clean workout name (Title Case).
- `repsText` should be a rep range if present (e.g., "10-12"), else "reps".
- `wtsText` default "wts".
- Do NOT invent exercises not implied by the text.
- Keep order as written.

Return schema:
{
  "workouts": [
    { "name": "Lat Pulldown", "wtsText": "wts", "repsText": "10-12" }
  ]
}

User text will be provided in the user message.
"""

    private static let generatorPrompt = """
You are a strength training routine generator.
You MUST output valid JSON only (no markdown, no extra text).

Constraints rules:
- If `bodyweightOnly=true`: use ONLY bodyweight exercises (no equipment at all).
- If `noGym=true` or `atHome=true`: do NOT use gym machines/cables.
- If `noDumbbells=true`: do NOT use dumbbells. (Bodyweight, bands, pull-up bar, backpack, chair are allowed unless bodyweightOnly=true.)
- Choose exercises appropriate to the requested day (push/pull/legs).
- 6–8 exercises.

Output schema (EXACT):
{
  "workoutList": "<Exercise Name> x <sets> <reps> and <Exercise Name> x <sets> <reps> and ...",
  "notes": "short string, optional"
}

Formatting rules for workoutList:
- Single line string.
- Use exactly “ x ” between exercise and sets (example: “Push-Up x 3 8-12”).
- Use “ and ” between exercises (not commas/bullets).
- Sets are integers (3 or 4).
- Reps are ranges like “8-12”, “10-12”, “12-15”.
- Title Case exercise names.
- No warmups, no explanations.
"""
}

private struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let response_format: ResponseFormat?
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Codable {
    let type: String
}

private struct OpenAIChatResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let role: String
        let content: String
    }
}

private extension OpenAIChatClient {
    /// Builds an authorized OpenAI chat completion request using the current config.
    /// Change impact: Adjust headers or payload fields to alter how the app talks to OpenAI.
    static func buildRequest(messages: [ChatMessage], temperature: Double, responseFormat: ResponseFormat?) throws -> URLRequest {
        guard let apiKey = OpenAIConfig.apiKey, !apiKey.isEmpty else {
            throw OpenAIError(statusCode: nil, message: "Missing OpenAI API key.")
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OpenAIChatRequest(
            model: OpenAIConfig.model,
            messages: messages,
            temperature: temperature,
            response_format: responseFormat
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    /// Executes a URL request and ensures an HTTP response is returned.
    /// Change impact: Update error handling or logging to change how network failures surface in-app.
    static func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError(statusCode: nil, message: "Invalid response.")
        }

        #if DEBUG
        print("[AI] HTTP status: \(http.statusCode)")
        #endif

        guard 200..<300 ~= http.statusCode else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            let message = String(snippet.prefix(200))
            throw OpenAIError(statusCode: http.statusCode, message: message)
        }

        return (data, http)
    }
}
