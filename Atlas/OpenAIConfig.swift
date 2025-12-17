import Foundation

struct OpenAIConfig {
    static var apiKey: String? {
        let key = LocalSecrets.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static var model: String = "gpt-4o-mini"
}
