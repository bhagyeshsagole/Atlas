//
//  OpenAIChatClient.swift
//  Atlas
//
//  What this file is:
//  - Low-level HTTP client for OpenAI chat calls used to parse routines and generate summaries/coaching.
//
//  Where it’s used:
//  - Called by `RoutineAIService` to build/repair routine JSON and create post-workout summaries.
//  - Provides request builders and response parsing helpers shared across AI flows.
//
//  Called from:
//  - `RoutineAIService` generate/repair/summary/coaching functions invoke these helpers before parsing responses.
//
//  Key concepts:
//  - Each OpenAI request is built from `ChatMessage` arrays and proxied through a Supabase Edge Function (server-side key).
//  - Responses may include code fences; we strip them before decoding JSON.
//
//  Safe to change:
//  - Prompt text, temperature, or logging, as long as JSON decoding expectations stay aligned.
//
//  NOT safe to change:
//  - Response parsing structure (choices/message/content) without updating all callers.
//  - Error handling paths that surface status codes to the UI.
//
//  Common bugs / gotchas:
//  - Supabase auth is required; unauthenticated requests will throw/return fallback responses.
//  - Returning anything other than valid JSON in repair flows will trip the decoding guardrails.
//
//  DEV MAP:
//  - See: DEV_MAP.md → D) AI / OpenAI
//
// FLOW SUMMARY:
// RoutineAIService builds prompts → OpenAIChatClient assembles request → OpenAI returns text/JSON → helper strips code fences → caller decodes into app models.
//

import Foundation
import Supabase

fileprivate struct ChatMessage: Codable {
    let role: String
    let content: String
}

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
    /// Simple chat helper for generic prompts.
    static func chat(prompt: String) async throws -> String {
        let messages: [ChatMessage] = [
            .init(role: "user", content: prompt)
        ]
        let payload = try buildRequestPayload(messages: messages, temperature: 0.2, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        #if DEBUG
        print("[AI][CHAT] status=\(response.statusCode) ms=\(elapsed)")
        #endif
        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }
        return stripCodeFences(from: content).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    /// Sends a structured parsing request to OpenAI and maps the response to workout data.
    /// Change impact: Edit to reshape the parsing prompt, temperature, or JSON decoding strategy.
    static func parseRoutineWorkouts(rawText: String) async throws -> RoutineParseOutput {
        let messages: [ChatMessage] = [
            .init(role: "developer", content: Self.parserPrompt),
            .init(role: "user", content: rawText)
        ]
        let payload = try buildRequestPayload(messages: messages, temperature: 0.2, responseFormat: ResponseFormat(type: "json_object"))
        let (data, _) = try await perform(payload: payload)

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

        let payload = try buildRequestPayload(messages: messages, temperature: 0.3, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
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

        let payload = try buildRequestPayload(messages: messages, temperature: 0.1, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(payload: payload)
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

    /// Generates a concise summary for a routine. Returns plain text without markdown.
    static func generateRoutineSummary(
        routineTitle: String,
        workouts: [RoutineWorkout]
    ) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let workoutLines = workouts.map { workout in
            let reps = workout.repsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let wts = workout.wtsText.trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(workout.name): \(reps.isEmpty ? "reps" : reps) | \(wts.isEmpty ? "wts" : wts)"
        }.joined(separator: "\n")

        let userContent = """
Routine: \(routineTitle)
Exercises:
\(workoutLines)
Return 2-5 short lines, plain text only. No markdown, no bullets.
"""

        let messages: [ChatMessage] = [
            .init(role: "system", content: summarySystemPrompt),
            .init(role: "developer", content: summaryDeveloperPrompt),
            .init(role: "user", content: userContent)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.25, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
    }

    static func cleanExerciseName(raw: String) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let messages: [ChatMessage] = [
            .init(role: "system", content: "You are an expert exercise name editor. Return only the corrected, concise exercise title in Title Case. Do not add quotes or commentary."),
            .init(role: "user", content: raw)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.1, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
    }

    static func cleanRoutineTitle(rawTitle: String, workoutsPrompt: String) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let userContent = """
Raw title: "\(rawTitle)"
Routine description: "\(workoutsPrompt)"
Task:
- Fix spelling/casing
- Use the description to improve the title if needed
- Keep 2–5 words, optional parenthetical like "(Chest/Shoulders)" only if helpful
Return ONLY the title text.
"""

        let messages: [ChatMessage] = [
            .init(role: "system", content: cleanRoutineTitleSystemPrompt),
            .init(role: "user", content: userContent)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.15, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
    }

    static func cleanWorkoutName(raw: String) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let userContent = """
Raw name: "\(raw)"
Task:
- Fix spelling/casing
- Keep meaning
- Shorten only if overly verbose
Return ONLY the cleaned name.
"""

        let messages: [ChatMessage] = [
            .init(role: "system", content: cleanWorkoutNameSystemPrompt),
            .init(role: "user", content: userContent)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.1, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
    }

    /// Generates coaching tips and session targets for a specific exercise.
    static func generateExerciseCoaching(
        routineTitle: String,
        exerciseName: String,
        lastSessionSetsText: String,
        preferredUnit: WorkoutUnits
    ) async throws -> (suggestion: RoutineAIService.ExerciseSuggestion, status: Int, elapsedMs: Int) {
        let userContent = """
Routine: \(routineTitle)
Exercise: \(exerciseName)
Preferred unit: \(preferredUnit == .kg ? "kg" : "lb")
Last session sets (if any):
\(lastSessionSetsText.isEmpty ? "None" : lastSessionSetsText)
"""

        let messages: [ChatMessage] = [
            .init(role: "system", content: coachingSystemPrompt),
            .init(role: "developer", content: coachingDeveloperPrompt),
            .init(role: "user", content: userContent)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.25, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(payload: payload)
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
            let decoded = try JSONDecoder().decode(CoachingSuggestionResponse.self, from: jsonData)
            let suggestion = decoded.toSuggestion()
            #if DEBUG
            print("[AI][COACH] parsed=true")
            #endif
            return (suggestion, response.statusCode, elapsed)
        } catch {
            throw OpenAIError(statusCode: response.statusCode, message: "Failed to decode coaching JSON: \(error.localizedDescription)")
        }
    }

    static func generatePostWorkoutSummary(context: RoutineAIService.PostSummaryContext) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let contextString = buildPostSummaryContextString(context: context)
        let messages: [ChatMessage] = [
            .init(role: "system", content: postSummarySystemPrompt),
            .init(role: "developer", content: postSummaryDeveloperPrompt),
            .init(role: "user", content: contextString)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.25, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
    }

    static func repairPostWorkoutSummary(rawText: String) async throws -> (text: String, status: Int, elapsedMs: Int) {
        let messages: [ChatMessage] = [
            .init(role: "system", content: postSummaryRepairSystemPrompt),
            .init(role: "developer", content: postSummaryRepairDeveloperPrompt),
            .init(role: "user", content: rawText)
        ]

        let payload = try buildRequestPayload(messages: messages, temperature: 0.1, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(payload: payload)
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        let chatResponse = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw OpenAIError(statusCode: response.statusCode, message: "No content returned from OpenAI.")
        }

        let cleaned = stripCodeFences(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, response.statusCode, elapsed)
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

    private static let cleanRoutineTitleSystemPrompt = """
You are a naming assistant for gym routines.
"""

    private static let cleanWorkoutNameSystemPrompt = """
You clean gym exercise/workout names.
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

    private static let summarySystemPrompt = """
You summarize workout routines. You only return plain text (no markdown, no bullets).
Keep it scannable and helpful.
"""

    private static let summaryDeveloperPrompt = """
Return 2–5 short lines. Use concise labels like:
Focus: ...
Volume: ...
Rep ranges: ...
Tip: ...
Avoid fluff. Do not wrap in quotes or code fences.
"""

    private static let coachingSystemPrompt = """
You coach strength exercises. You return ONLY JSON. No markdown, no prose.
"""

    private static let coachingDeveloperPrompt = """
Return JSON matching:
{
  "techniqueTips": "short text",
  "thisSessionPlan": "short text",
  "suggestedWeight": { "value": 45.4, "unit": "kg" },
  "suggestedReps": "10-12",
  "suggestedTag": "S"
}
Rules:
- techniqueTips and thisSessionPlan must be concise (1-2 sentences each).
- suggestedTag is one of "W", "S", "DS" (default S).
- Always include suggestedWeight.value; convert to kg if unclear.
- Do NOT include markdown or bullets.
"""

    private static let postSummarySystemPrompt = """
You are a concise strength coach. You ONLY output JSON. No markdown, no extra text. Keep answers short, skimmable, and dense with value.
"""

    private static let postSummaryDeveloperPrompt = """
Return EXACTLY this JSON shape:
{
  "sessionDate": "December 24, 2025 (Wednesday)",
  "rating": 8.7,
  "insight": "One sentence, max ~90 chars, factoring routine coverage.",
  "prs": [
    "Bench Press: +5 lb at same reps",
    "Incline DB: +2 reps at 35s"
  ],
  "improvements": [
    "Bench: keep 52.2 kg | 115 lb and aim 7 reps with safeties/spotter.",
    "Incline DB: hit 35s for 10/10/10, then move to 40s.",
    "Add rear delts: reverse pec deck 2×12–15."
  ]
}
Rules:
- rating must be a number 0.0–10.0.
- insight is exactly one sentence (<= ~90 chars).
- prs max 2 items; improvements max 3 items; never empty improvements (minimum 2).
- Keep strings short. No paragraphs. No emojis. No markdown fences.
"""

    private static let postSummaryRepairSystemPrompt = """
You fix JSON. You ONLY output valid JSON matching the schema sent. No markdown.
"""

    private static let postSummaryRepairDeveloperPrompt = """
Repair the user's content into valid JSON matching the provided schema. Do not add commentary.
"""
}

private extension OpenAIChatClient {
    static func buildPostSummaryContextString(context: RoutineAIService.PostSummaryContext) -> String {
        var lines: [String] = []
        lines.append("Session date: \(context.sessionDate)")
        lines.append("Routine: \(context.routineTitle)")
        lines.append("Duration minutes: \(context.durationMinutes)")
        lines.append("Totals: sets=\(context.totals.sets), reps=\(context.totals.reps), volumeKg=\(String(format: "%.1f", context.totals.volumeKg)), volumeLb=\(String(format: "%.1f", context.totals.volumeLb))")
        lines.append("Unit preference: \(context.unitPreference == .kg ? "kg" : "lb")")
        lines.append("Exercises:")
        for ex in context.exercises {
            let prevLine: String
            if let prev = ex.previous {
                let bestPrev = prev.sets.max(by: { ($0.weightKg ?? 0) * Double($0.reps) < ($1.weightKg ?? 0) * Double($1.reps) })
                let bestPrevText = bestPrev.map { "prevTop=\(String(format: "%.1f", $0.weightKg ?? 0))kg x\($0.reps)" } ?? "prevTop=none"
                prevLine = bestPrevText
            } else {
                prevLine = "prevTop=none"
            }
            let currentSets = ex.sets.map { set in
                let weight = String(format: "%.1f", set.weightKg ?? 0)
                return "\(set.tag): \(weight)kg x\(set.reps)"
            }.joined(separator: "; ")
            lines.append("- \(ex.name) | muscles=\(ex.muscles.0)/\(ex.muscles.1) | sets=\(currentSets) | \(prevLine)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct OAChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let response_format: ResponseFormat?
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

private struct CoachingSuggestionResponse: Codable {
    struct SuggestedWeight: Codable {
        let value: Double
        let unit: String?
    }

    let techniqueTips: String
    let thisSessionPlan: String
    let suggestedWeight: SuggestedWeight?
    let suggestedReps: String?
    let suggestedTag: String?

    func toSuggestion() -> RoutineAIService.ExerciseSuggestion {
        var weightKg: Double?
        if let weight = suggestedWeight {
            if weight.unit?.lowercased() == "lb" {
                weightKg = weight.value / WorkoutSessionFormatter.kgToLb
            } else {
                weightKg = weight.value
            }
        }

        return RoutineAIService.ExerciseSuggestion(
            techniqueTips: techniqueTips.trimmingCharacters(in: .whitespacesAndNewlines),
            thisSessionPlan: thisSessionPlan.trimmingCharacters(in: .whitespacesAndNewlines),
            suggestedWeightKg: weightKg,
            suggestedReps: (suggestedReps ?? "10-12").trimmingCharacters(in: .whitespacesAndNewlines),
            suggestedTag: (suggestedTag ?? "S").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        )
    }
}

private extension OpenAIChatClient {
    /// Builds the chat payload that the Supabase Edge Function will forward to OpenAI.
    static func buildRequestPayload(messages: [ChatMessage], temperature: Double, responseFormat: ResponseFormat?) throws -> OAChatRequest {
        OAChatRequest(
            model: OpenAIConfig.model,
            messages: messages,
            temperature: temperature,
            response_format: responseFormat
        )
    }

    /// Invokes the Supabase Edge Function that proxies to OpenAI using server-held secrets.
    static func perform(payload: OAChatRequest) async throws -> (Data, HTTPURLResponse) {
        try await AIProxy.ensureHealthy()
        return try await EdgeFunctionClient.callChat(payload: payload)
    }
}
