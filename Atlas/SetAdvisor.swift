//
//  SetAdvisor.swift
//  Atlas
//
//  Pure-Swift helper for smart set logging features:
//  - Auto-detect tag (warmup/working/drop)
//  - PR detection and nudge
//  - Auto progression suggestion
//  - Fatigue guardrail
//  - Target remaining calculation
//
//  This file contains no UI code and is designed to be testable.
//

import Foundation

// MARK: - SetAdvisor

enum SetAdvisor {

    // MARK: - Data Structures

    struct SetData {
        let weightKg: Double?
        let reps: Int
        let tag: String // "W", "S", "DS"
        let createdAt: Date
    }

    struct ProgressionSuggestion {
        let weightKg: Double?
        let reps: Int
        let reason: String // e.g., "+1 rep", "+2.5 lb"
    }

    struct TargetRemaining {
        let workingSetsRemaining: Int
        let repsRemaining: Int
        let repRangeLower: Int
        let repRangeUpper: Int
    }

    struct SetNote {
        let text: String
        let isPR: Bool
    }

    // MARK: - Auto-detect Tag

    /// Determines the suggested tag for the next set based on:
    /// - If no sets logged yet -> Warmup
    /// - If weight < 70% of rolling median working weight -> Warmup
    /// - If weight decreasing after a top set -> Drop
    /// - Otherwise -> Working
    static func suggestTag(
        enteredWeightKg: Double?,
        thisSessionSets: [SetData],
        historicalWorkingSets: [SetData], // Working sets from last 8 weeks
        lastUsedTag: String?
    ) -> String {
        // If no sets logged yet, default to Warmup
        if thisSessionSets.isEmpty {
            return "W"
        }

        guard let enteredWeightKg, enteredWeightKg > 0 else {
            // Bodyweight - use last used tag or Working
            return lastUsedTag ?? "S"
        }

        // Compute rolling median of historical working weights
        let workingWeights = historicalWorkingSets
            .filter { $0.tag == "S" }
            .compactMap { $0.weightKg }

        let medianWeight: Double?
        if !workingWeights.isEmpty {
            let sorted = workingWeights.sorted()
            let mid = sorted.count / 2
            medianWeight = sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2
                : sorted[mid]
        } else {
            medianWeight = nil
        }

        // Check if this is a warmup based on percentage of median
        if let median = medianWeight, enteredWeightKg < median * 0.70 {
            return "W"
        }

        // Check if weight is among the lightest 1-2 in this session
        let thisSessionWeights = thisSessionSets.compactMap { $0.weightKg }.sorted()
        if thisSessionWeights.count >= 2 {
            let secondLowest = thisSessionWeights[min(1, thisSessionWeights.count - 1)]
            if enteredWeightKg <= secondLowest {
                // Could be warmup if early in session
                let workingSetsCount = thisSessionSets.filter { $0.tag == "S" }.count
                if workingSetsCount == 0 {
                    return "W"
                }
            }
        }

        // Check for drop set: weight decreasing after a top/working set
        let workingSetsThisSession = thisSessionSets.filter { $0.tag == "S" }
        if let lastWorking = workingSetsThisSession.last,
           let lastWorkingWeight = lastWorking.weightKg,
           enteredWeightKg < lastWorkingWeight * 0.85 {
            return "DS"
        }

        // Default to Working
        return "S"
    }

    // MARK: - PR Detection

    /// Checks if a set would be a PR based on:
    /// - Best weight at ≥5 reps, OR
    /// - Best weight × reps (volume)
    /// Returns (isPR, isCloseToPR)
    static func checkPRStatus(
        weightKg: Double?,
        reps: Int,
        historicalBestWeightAt5Plus: Double?,
        historicalBestVolume: Double? // weight × reps
    ) -> (isPR: Bool, isCloseToPR: Bool) {
        guard let weightKg, weightKg > 0, reps > 0 else {
            return (false, false)
        }

        let currentVolume = weightKg * Double(reps)

        // Check weight PR (at 5+ reps)
        var isWeightPR = false
        var isCloseToWeightPR = false
        if reps >= 5 {
            if let bestWeight = historicalBestWeightAt5Plus {
                if weightKg > bestWeight {
                    isWeightPR = true
                } else if weightKg >= bestWeight * 0.98 {
                    isCloseToWeightPR = true
                }
            } else {
                // No historical data, this is the first PR
                isWeightPR = true
            }
        }

        // Check volume PR
        var isVolumePR = false
        var isCloseToVolumePR = false
        if let bestVolume = historicalBestVolume {
            if currentVolume > bestVolume {
                isVolumePR = true
            } else if currentVolume >= bestVolume * 0.98 {
                isCloseToVolumePR = true
            }
        } else if weightKg > 0 && reps >= 5 {
            // No historical data, this is the first PR
            isVolumePR = true
        }

        return (isWeightPR || isVolumePR, isCloseToWeightPR || isCloseToVolumePR)
    }

    // MARK: - Set Notes

    /// Generates a meaningful note for a logged set
    static func generateSetNote(
        set: SetData,
        setIndex: Int,
        allSessionSets: [SetData],
        historicalBestWeightAt5Plus: Double?,
        historicalBestVolume: Double?
    ) -> SetNote? {
        guard let weightKg = set.weightKg, weightKg > 0 else {
            return nil
        }

        let currentVolume = weightKg * Double(set.reps)

        // Check for PR
        let prStatus = checkPRStatus(
            weightKg: weightKg,
            reps: set.reps,
            historicalBestWeightAt5Plus: historicalBestWeightAt5Plus,
            historicalBestVolume: historicalBestVolume
        )

        if prStatus.isPR {
            return SetNote(text: "PR", isPR: true)
        }

        if prStatus.isCloseToPR {
            return SetNote(text: "Close to PR", isPR: false)
        }

        // Find top set (highest weight, tie-break by reps)
        let workingSets = allSessionSets.filter { $0.tag == "S" && $0.weightKg != nil }
        if let topSet = workingSets.max(by: { a, b in
            let aWeight = a.weightKg ?? 0
            let bWeight = b.weightKg ?? 0
            if aWeight == bWeight {
                return a.reps < b.reps
            }
            return aWeight < bWeight
        }) {
            let topWeight = topSet.weightKg ?? 0
            let isTopSet = weightKg == topWeight && set.reps >= topSet.reps

            if isTopSet && set.tag == "S" {
                // Check if this is THE top set (not just tied)
                let topSetsCount = workingSets.filter { ($0.weightKg ?? 0) == topWeight }.count
                if topSetsCount == 1 || (setIndex == workingSets.firstIndex(where: { ($0.weightKg ?? 0) == topWeight }) ?? -1) {
                    return SetNote(text: "Top set", isPR: false)
                }
            }

            // Check for back-off (follows a top set with lower weight)
            if setIndex > 0 && set.tag == "S" {
                let previousSets = Array(allSessionSets.prefix(setIndex))
                if let lastTopIndex = previousSets.lastIndex(where: { ($0.weightKg ?? 0) == topWeight && $0.tag == "S" }),
                   weightKg < topWeight {
                    // This is a back-off set
                    return SetNote(text: "Back-off", isPR: false)
                }
            }
        }

        // Check for rep drop (reps decreased by ≥2 vs previous working set at similar weight)
        let previousWorkingSets = allSessionSets.prefix(setIndex).filter { $0.tag == "S" }
        if let lastSimilarSet = previousWorkingSets.last(where: {
            guard let w = $0.weightKg else { return false }
            return abs(w - weightKg) < weightKg * 0.05 // Within 5% weight
        }) {
            if set.reps <= lastSimilarSet.reps - 2 {
                return SetNote(text: "Rep drop", isPR: false)
            }
        }

        return nil
    }

    // MARK: - Fatigue Guardrail

    /// Detects fatigue based on:
    /// - Last 2 working sets show decreasing reps (≥2 total drop) AND weight not increasing
    /// - User is below target rep range floor for 2 consecutive working sets
    static func detectFatigue(
        thisSessionSets: [SetData],
        targetRepRangeLower: Int?
    ) -> (isFatigued: Bool, message: String?) {
        let workingSets = thisSessionSets.filter { $0.tag == "S" }

        guard workingSets.count >= 2 else {
            return (false, nil)
        }

        let lastTwo = Array(workingSets.suffix(2))
        let set1 = lastTwo[0]
        let set2 = lastTwo[1]

        // Check decreasing reps with same or lower weight
        let weight1 = set1.weightKg ?? 0
        let weight2 = set2.weightKg ?? 0

        if weight2 <= weight1 && set2.reps < set1.reps {
            let totalRepDrop = set1.reps - set2.reps
            if totalRepDrop >= 2 {
                return (true, "Fatigue detected — consider lowering weight or ending here")
            }
        }

        // Check if below target rep range for 2 consecutive sets
        if let targetLower = targetRepRangeLower {
            let belowTarget = lastTwo.filter { $0.reps < targetLower }
            if belowTarget.count >= 2 {
                return (true, "Reps below target range — consider adjusting weight")
            }
        }

        return (false, nil)
    }

    // MARK: - Auto Progression

    /// Suggests the next set based on last session's best comparable working set:
    /// - +1 rep at same weight (preferred)
    /// - +2.5 lb / +1.25 kg if reps already at top of range
    static func suggestProgression(
        lastSessionBestWorkingSet: SetData?,
        targetRepRangeUpper: Int,
        isMetricUnit: Bool // true = kg, false = lb
    ) -> ProgressionSuggestion? {
        guard let lastBest = lastSessionBestWorkingSet,
              let lastWeight = lastBest.weightKg,
              lastWeight > 0 else {
            return nil
        }

        // If reps are at or above top of range, suggest weight increase
        if lastBest.reps >= targetRepRangeUpper {
            let increment = isMetricUnit ? 1.25 : 2.5 // kg or lb
            let incrementKg = isMetricUnit ? increment : increment / 2.205
            let newWeight = lastWeight + incrementKg
            let displayIncrement = isMetricUnit ? "+1.25 kg" : "+2.5 lb"

            return ProgressionSuggestion(
                weightKg: newWeight,
                reps: targetRepRangeUpper - 2, // Reset to lower-mid range
                reason: displayIncrement
            )
        }

        // Otherwise suggest +1 rep at same weight
        return ProgressionSuggestion(
            weightKg: lastWeight,
            reps: lastBest.reps + 1,
            reason: "+1 rep"
        )
    }

    // MARK: - Target Remaining

    /// Parses plan text and calculates remaining sets/reps
    /// Expected format: "Warmup: light × 8–12 reps\nWorking: 3–4 sets × 6–10 reps"
    static func calculateTargetRemaining(
        planText: String,
        workingSetsLogged: Int
    ) -> TargetRemaining {
        // Default values
        var targetWorkingSetsMin = 3
        var repRangeLower = 6
        var repRangeUpper = 12

        // Extract the Working line if present
        let workingLine: String
        if let workingRange = planText.range(of: "Working:", options: .caseInsensitive) {
            let afterWorking = planText[workingRange.upperBound...]
            // Take until the next newline or end of string
            if let newlineRange = afterWorking.range(of: "\n") {
                workingLine = String(afterWorking[..<newlineRange.lowerBound])
            } else {
                workingLine = String(afterWorking)
            }
        } else {
            workingLine = planText
        }

        // Parse sets: look for patterns like "3–4 sets" or "3-4 sets" or "3 sets"
        let setsPattern = #"(\d+)[–\-]?(\d+)?\s*sets?"#
        if let setsMatch = workingLine.range(of: setsPattern, options: .regularExpression) {
            let matchString = String(workingLine[setsMatch])
            let numbers = matchString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
            if let first = numbers.first {
                targetWorkingSetsMin = first
            }
        }

        // Parse reps: look for patterns like "6–10 reps" or "6-10 reps" in the Working line
        let repsPattern = #"(\d+)[–\-](\d+)\s*reps"#
        if let repsMatch = workingLine.range(of: repsPattern, options: .regularExpression) {
            let matchString = String(workingLine[repsMatch])
            let numbers = matchString.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
            if numbers.count >= 2 {
                repRangeLower = numbers[0]
                repRangeUpper = numbers[1]
            }
        }

        let remainingSets = max(0, targetWorkingSetsMin - workingSetsLogged)
        let remainingReps = remainingSets * repRangeLower

        return TargetRemaining(
            workingSetsRemaining: remainingSets,
            repsRemaining: remainingReps,
            repRangeLower: repRangeLower,
            repRangeUpper: repRangeUpper
        )
    }

    // MARK: - Historical Data Helpers

    /// Finds the best weight at 5+ reps from historical sets
    static func findBestWeightAt5PlusReps(from sets: [SetData]) -> Double? {
        let qualifying = sets.filter { $0.reps >= 5 && $0.tag == "S" }
        return qualifying.compactMap { $0.weightKg }.max()
    }

    /// Finds the best volume (weight × reps) from historical sets
    static func findBestVolume(from sets: [SetData]) -> Double? {
        let volumes = sets
            .filter { $0.tag == "S" }
            .compactMap { set -> Double? in
                guard let w = set.weightKg else { return nil }
                return w * Double(set.reps)
            }
        return volumes.max()
    }

    /// Finds the best working set from a session (highest weight, tie-break by reps)
    static func findBestWorkingSet(from sets: [SetData]) -> SetData? {
        let workingSets = sets.filter { $0.tag == "S" && $0.weightKg != nil }
        return workingSets.max { a, b in
            let aWeight = a.weightKg ?? 0
            let bWeight = b.weightKg ?? 0
            if aWeight == bWeight {
                return a.reps < b.reps
            }
            return aWeight < bWeight
        }
    }
}
