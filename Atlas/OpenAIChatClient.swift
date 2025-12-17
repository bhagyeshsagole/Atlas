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

struct OpenAIChatClient {
    /// VISUAL TWEAK: Change endpoint or request parameters here to affect how parsing calls are sent.
    static func parseRoutineWorkouts(rawText: String) async throws -> RoutineParseOutput {
        let messages: [ChatMessage] = [
            .init(role: "developer", content: Self.prompt),
            .init(role: "user", content: rawText)
        ]
        let request = try buildRequest(messages: messages, temperature: 0.2, responseFormat: ResponseFormat(type: "json_object"))
        let (data, _) = try await perform(request: request)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw NSError(domain: "OpenAIChatClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "No content returned from OpenAI."])
        }

        #if DEBUG
        print("[AI] OpenAI response received.")
        #endif

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "OpenAIChatClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode model response."])
        }

        do {
            return try JSONDecoder().decode(RoutineParseOutput.self, from: jsonData)
        } catch {
            throw NSError(domain: "OpenAIChatClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode routine JSON: \(error.localizedDescription)"])
        }
    }

    /// VISUAL TWEAK: Change request body composition here to affect prompt strictness or creativity.
    static func generateWorkoutListString(requestText: String, routineTitleHint: String?) async throws -> String {
        var userContent = requestText
        if let routineTitleHint, !routineTitleHint.isEmpty {
            userContent += "\nTitle: \(routineTitleHint)"
        }

        let messages: [ChatMessage] = [
            .init(role: "developer", content: generatorPrompt),
            .init(role: "user", content: userContent)
        ]
        let request = try buildRequest(messages: messages, temperature: 0.25, responseFormat: nil)
        let (data, _) = try await perform(request: request)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw NSError(domain: "OpenAIChatClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "No content returned from OpenAI."])
        }
        return stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
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
Return ONLY a single-line workout list string, no bullets, no numbering, no quotes, no JSON.

Format rules:
- Use exactly: "<Exercise Name> x <sets> <reps> and <Exercise Name> x <sets> <reps> and ..."
- Sets are integers like 3 or 4.
- Reps are a range like "8-12" or "10-12".
- Use Title Case exercise names.
- Do NOT include warmups.
- Do NOT include explanations.
- Output 6–8 exercises appropriate for the request.

User text will be provided in the user message.
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
    static func buildRequest(messages: [ChatMessage], temperature: Double, responseFormat: ResponseFormat?) throws -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(OpenAIConfig.apiKey)", forHTTPHeaderField: "Authorization")
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

    static func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIChatClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response."])
        }

        #if DEBUG
        print("[AI] HTTP status: \(http.statusCode)")
        #endif

        guard 200..<300 ~= http.statusCode else {
            #if DEBUG
            if http.statusCode == 401 {
                print("[AI] Error: Unauthorized (check API key).")
            } else if http.statusCode == 429 {
                print("[AI] Error: Rate limited or quota exceeded.")
            }
            let snippet = String(data: data, encoding: .utf8) ?? ""
            print("[AI] Response snippet: \(snippet.prefix(200))")
            #endif
            throw NSError(domain: "OpenAIChatClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI responded with an error."])
        }

        return (data, http)
    }
}
