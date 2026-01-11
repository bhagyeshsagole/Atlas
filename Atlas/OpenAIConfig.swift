//
//  OpenAIConfig.swift
//  Atlas
//
//  What this file is:
//  - Central place to configure AI calls (model + Supabase function routing).
//
//  Where it’s used:
//  - Read by `RoutineAIService` and `OpenAIChatClient` before any AI network call.
//
//  Called from:
//  - `RoutineAIService` and `OpenAIChatClient` access `model` before sending requests.
//
//  Key concepts:
//  - OpenAI API key is never bundled in the app; calls are proxied through a Supabase Edge Function.
//
//  Safe to change:
//  - Default model string or debug logging.
//
//  NOT safe to change:
//  - Supabase routing without also updating the Edge Function name/contract.
//
//  Common bugs / gotchas:
//  - Supabase client must be configured and authenticated before AI calls will succeed.
//
//  DEV MAP:
//  - See: DEV_MAP.md → D) AI / OpenAI
//
import Foundation
import Supabase

struct OpenAIConfig {
    static let model: String = "gpt-4o-mini"

    static var supabaseClient: SupabaseClient? {
        SupabaseClientProvider.makeClient()
    }

    static var functionName: String { AIProxy.functionName }

    static var functionURLString: String? {
        guard let base = SupabaseConfig.url else { return nil }
        return AIProxy.endpointString(baseURL: base)
    }

    static var isAIAvailable: Bool {
        guard let client = supabaseClient else { return false }
        guard let session = client.auth.currentSession, session.isExpired == false else { return false }
        return true
    }
}
