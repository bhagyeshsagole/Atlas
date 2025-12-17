import Foundation

struct OpenAIConfig {
    static var apiKey: String {
        let key = LocalSecrets.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            fatalError("Missing OpenAI API key. Add it to Atlas/Config/LocalSecrets.swift (gitignored).")
        }
        return key
    }

    static var model: String = "gpt-4o-mini"
}
