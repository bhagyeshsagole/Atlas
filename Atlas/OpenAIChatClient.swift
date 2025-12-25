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

        let request = try buildRequest(messages: messages, temperature: 0.25, responseFormat: nil)
        let start = Date()
        let (data, response) = try await perform(request: request)
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

        let request = try buildRequest(messages: messages, temperature: 0.25, responseFormat: ResponseFormat(type: "json_object"))
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

        let request = try buildRequest(messages: messages, temperature: 0.25, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(request: request)
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

        let request = try buildRequest(messages: messages, temperature: 0.1, responseFormat: ResponseFormat(type: "json_object"))
        let start = Date()
        let (data, response) = try await perform(request: request)
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
  "tldr": [
    "Push day — Chest/Triceps focus",
    "Volume: 4,820 kg | 10,626 lb · 18 sets · 156 reps",
    "Best set: 45.4 kg | 100 lb × 8 (Bench Press)",
    "Progress: Bench +2 reps @ 45.4 kg | 100 lb",
    "Next: Keep 45.4 kg | 100 lb and aim 10/9/8"
  ],
  "sections": {
    "trained": [
      { "exercise": "Bench Press", "muscles": "Chest · Triceps · Front delts", "best": "45.4 kg | 100 lb × 8", "sets": 3, "note": "Form stayed tight" }
    ],
    "progress": [
      { "exercise": "Bench Press", "delta": "+2 reps @ 45.4 kg | 100 lb", "confidence": "high" }
    ],
    "whatsNext": {
      "focus": "Push day — prioritize chest + triceps",
      "targets": [
        "Bench Press — 45.4 kg | 100 lb × 10/9/8",
        "Incline DB Press — 22.7 kg | 50 lb × 10/10/8"
      ],
      "note": "Keep rest 90–120s on compounds."
  },
  "quality": {
    "rating": 8,
    "reasons": ["Strong chest volume", "Triceps hit consistently", "Missing lateral delts"]
  }
}
}
Rules:
- rating must be an integer 1-10.
- Never return empty arrays if the session has sets; always include at least one trained item.
- Keep strings short. No paragraphs. No emojis. No markdown fences.
- Exercises: max 8 items. Progress highlights: max 2. Each line max ~60 chars.
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
