import Foundation

struct OpenAIConfig {
    static var apiKey: String? {
        let localKey = LocalSecrets.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localKey.isEmpty {
            #if DEBUG
            print("[AI] Key present: true")
            #endif
            return localKey
        }

        #if DEBUG
        print("[AI] Key present: false")
        #endif
        return nil
    }

    static var model: String = "gpt-4o-mini"
}
