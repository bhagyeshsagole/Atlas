//
//  OpenAIConfig.swift
//  Atlas
//
//  What this file is:
//  - Central place to read the OpenAI API key and set the model name used by AI requests.
//
//  Where it’s used:
//  - Read by `RoutineAIService` and `OpenAIChatClient` before any network call.
//
//  Key concepts:
//  - API key is pulled from `LocalSecrets` at call time so the app can start without a key present.
//
//  Safe to change:
//  - Default model string or debug logging.
//
//  NOT safe to change:
//  - How the key is trimmed/checked; skipping the empty check will crash when the key is missing.
//
//  Common bugs / gotchas:
//  - Committing a real API key is unsafe; keep real keys in local-only files.
//  - If you leave the key empty, AI features will throw `missingAPIKey` errors.
//
//  DEV MAP:
//  - See: DEV_MAP.md → D) AI / OpenAI
//
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
