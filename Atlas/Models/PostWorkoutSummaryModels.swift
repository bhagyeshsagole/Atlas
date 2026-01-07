//
//  PostWorkoutSummaryModels.swift
//  Atlas
//
//  What this file is:
//  - Codable models that define the JSON shape of AI post-workout summaries.
//
//  Where it’s used:
//  - Decoded from OpenAI responses in `RoutineAIService` and displayed in `PostWorkoutSummaryView`.
//
//  Called from:
//  - `RoutineAIService` decodes/encodes these models; `PostWorkoutSummaryView` renders their fields.
//
//  Key concepts:
//  - Optional fields keep compatibility with older AI responses so decoding doesn’t crash.
//
//  Safe to change:
//  - Add optional fields when expanding the summary schema while updating prompts accordingly.
//
//  NOT safe to change:
//  - Remove or rename fields without updating prompts and decoding; existing cached summaries could fail to load.
//
//  Common bugs / gotchas:
//  - Keep legacy nested structs optional; making them non-optional will break older cache entries.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Post-Workout Summary (AI)
//
import Foundation

/// DEV NOTE: This is the single source of truth for post-workout summary JSON models.
/// DEV NOTE: If you need to change the AI schema, update these structs + the prompt builder in RoutineAIService.
struct PostWorkoutSummaryPayload: Codable {
    let sessionDate: String
    let rating: Double?
    let insight: String?
    let prs: [String]?
    let improvements: [String]?

    // Legacy fields kept optional for backward compatibility.
    struct SectionData: Codable {
        struct TrainedItem: Codable, Hashable {
            let exercise: String
            let muscles: String
            let best: String
            let sets: Int
            let note: String
        }

        struct ProgressItem: Codable, Hashable {
            let exercise: String
            let delta: String
            let confidence: String
        }

        struct WhatsNext: Codable, Hashable {
            let focus: String
            let targets: [String]
            let note: String
        }

        struct Quality: Codable, Hashable {
            let rating: Int
            let reasons: [String]
        }

        let trained: [TrainedItem]
        let progress: [ProgressItem]
        let whatsNext: WhatsNext
        let quality: Quality
    }

    let tldr: [String]?
    let sections: SectionData?
}
