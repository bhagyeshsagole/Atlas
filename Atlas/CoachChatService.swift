import Foundation

struct MuscleCoachContext: Identifiable, Hashable {
    var id: String { "\(bucket.id)-\(selectedRange.rawValue)" }
    let selectedRange: StatsLens
    let bucket: MuscleGroup
    let score: Int
    let reasons: [String]
    let suggestions: [String]
}

struct CoachChatMessage: Identifiable, Hashable {
    enum Role {
        case assistant, user
    }
    let id = UUID()
    let role: Role
    let text: String
}

enum CoachChatService {
    static func reply(to userMessage: String, context: MuscleCoachContext) async throws -> String {
        guard OpenAIConfig.isAIAvailable else {
            return fallbackReply(for: context, userMessage: userMessage)
        }

        let intro = introContext(for: context)
        let userContent = """
\(intro)
User asked: "\(userMessage)"
"""
        let prompt = """
System:
\(systemPrompt)

User:
\(userContent)
"""
        return try await OpenAIChatClient.chat(prompt: prompt)
    }

    private static func introContext(for context: MuscleCoachContext) -> String {
        let reasons = context.reasons.isEmpty ? "No reasons available yet." : context.reasons.joined(separator: " • ")
        let suggestions = context.suggestions.isEmpty ? "Log more sets to get tailored suggestions." : context.suggestions.joined(separator: " • ")
        return """
Range: \(context.selectedRange.rawValue)
Muscle: \(context.bucket.displayName)
Score: \(context.score)/10
Why: \(reasons)
Suggestions: \(suggestions)
"""
    }

    private static func fallbackReply(for context: MuscleCoachContext, userMessage: String) -> String {
        let intro = introContext(for: context)
        return """
Coach context:
\(intro)
No live AI available. Focus on: \(context.suggestions.first ?? "add a primary lift and an accessory for balance"). Keep logging and ask again.
"""
    }

    private static let systemPrompt = """
You are Titan, a concise strength coach. Use the provided score, reasons, and suggestions to give specific guidance. Be short, clear, and actionable. Assume beginner to intermediate lifter. Avoid fluff. Mention 2–4 concrete exercises with sets/reps when relevant.
"""
}
