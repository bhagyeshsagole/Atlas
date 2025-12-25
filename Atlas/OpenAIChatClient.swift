//
//  OpenAIChatClient.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//
//  Update: Hardened AI pipeline with generate/repair stages, structured logging, and safer timeouts

import Foundation

struct RoutineParseOutput: Codable {
    let workouts: [RoutineParseWorkout]
}

struct RoutineParseWorkout: Codable {
    let name: String
    let wtsText: String
    let repsText: String
}

struct RepairedWorkout: Codable {
    let name: String
    let sets: Int?
    let reps: String?
}

struct RepairedWorkoutsResponse: Codable {
    let workouts: [RepairedWorkout]
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
            .init(role: "developer", content: Self.parserPrompt),
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

    /// Stage A: Generate free-form routine text.
    static func generateRoutineFreeform(
        requestText: String,
        constraints: RoutineAIService.RoutineConstraints,
        requestId: String
    ) async throws -> (text: String, status: Int, elapsedMs: Int) {
        var userContent = "Request: \(requestText)\n"
        userContent += "Constraints detected: atHome=\(constraints.atHome), noGym=\(constraints.noGym), noDumbbells=\(constraints.noDumbbells), noMachines=\(constraints.noMachines), bodyweightOnly=\(constraints.bodyweightOnly)"

        let messages: [ChatMessage] = [
            .init(role: "system", content: generateSystemPrompt),
            .init(role: "developer", content: generateDeveloperPrompt),
            .init(role: "user", content: userContent)
        ]

        let request = try buildRequest(messages: messages, temperature: 0.3, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(request: request)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        #if DEBUG
        print("[AI][\(requestId)] stage=generate model=\(OpenAIConfig.model) status=\(response.statusCode) ms=\(elapsed)")
        #endif

        return (stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines), response.statusCode, elapsed)
    }

    /// Stage B/C: Repair routine text into strict JSON.
    static func repairRoutine(
        rawText: String,
        constraints: RoutineAIService.RoutineConstraints,
        requestId: String,
        strict: Bool
    ) async throws -> (response: RepairedWorkoutsResponse, status: Int, elapsedMs: Int) {
        var userContent = """
Raw routine text:
\"\"\"
\(rawText)
\"\"\"
Constraints detected: atHome=\(constraints.atHome), noGym=\(constraints.noGym), noDumbbells=\(constraints.noDumbbells), noMachines=\(constraints.noMachines), bodyweightOnly=\(constraints.bodyweightOnly)
Return JSON now.
"""
        if strict {
            userContent.append("\nIf you output anything except valid JSON, you failed.")
        }

        let messages: [ChatMessage] = [
            .init(role: "system", content: repairSystemPrompt),
            .init(role: "developer", content: repairDeveloperPrompt),
            .init(role: "user", content: userContent)
        ]

        let request = try buildRequest(messages: messages, temperature: 0.1, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(request: request)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw OpenAIError(statusCode: response.statusCode, message: "Unable to encode model response.")
        }

        do {
            let decoded = try JSONDecoder().decode(RepairedWorkoutsResponse.self, from: jsonData)
            #if DEBUG
            print("[AI][\(requestId)] stage=\(strict ? "repair2" : "repair") model=\(OpenAIConfig.model) status=\(response.statusCode) ms=\(elapsed) workouts=\(decoded.workouts.count)")
            #endif
            return (decoded, response.statusCode, elapsed)
        } catch {
            throw OpenAIError(statusCode: response.statusCode, message: "Failed to decode workout JSON: \(error.localizedDescription)")
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

    private static let parserPrompt = """
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

    private static let generateSystemPrompt = """
You are a strength training coach. The user may be vague (e.g., “Forearms workout”).
Your job is to propose a routine that matches the request and constraints. Keep it concise.
"""

    private static let generateDeveloperPrompt = """
Return a routine with 6–8 exercises whenever possible.
If the user does not specify equipment, assume normal gym access.
If the user says “at home” / “no gym” / “no dumbbells” / “no machines” / “bodyweight only”, respect it.
Prefer simple, common exercise names.
Try to include sets + rep ranges, but it’s okay if you don’t.
"""

    private static let repairSystemPrompt = """
You are a formatter. You ONLY output valid JSON. No markdown. No commentary.
"""

    private static let repairDeveloperPrompt = """
Convert the provided routine text into the JSON schema below.
If any exercise is missing sets/reps, fill defaults: sets=3, reps="10-12".
Guarantee at least 5 exercises (prefer 6–8). If fewer, add more consistent exercises.
Use Title Case for exercise names.

JSON schema (EXACT KEYS):
{
  "workouts": [
    { "name": "Exercise Name", "sets": 3, "reps": "10-12" }
  ]
}
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
        request.timeoutInterval = 25

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
