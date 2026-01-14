//
//  ExerciseClassifier.swift
//  Atlas
//
//  What this file is:
//  - Deterministic exercise-to-muscle-group classifier using rule-based keywords.
//
//  Where it's used:
//  - Stats view for correct muscle group categorization
//  - Key Lifts manager for category organization
//
//  Key concepts:
//  - Rule-based classification takes precedence over any AI classification
//  - Normalized names (lowercase, trimmed) for consistent matching
//  - 8 distinct categories: Arms, Back, Biceps, Chest, Core, Legs, Triceps, Shoulders
//
//  Safe to change:
//  - Add more keyword patterns for better matching
//
//  NOT safe to change:
//  - Category names without updating all consumers
//  - Removing normalization logic
//

import Foundation

struct ExerciseClassifier {
    /// Normalize exercise name for consistent matching
    static func normalize(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Classify exercise into primary muscle group using rule-based keywords
    static func classify(_ name: String) -> MuscleGroup {
        let normalized = normalize(name)

        // LEGS - must check first due to "leg extension" vs "extension"
        if normalized.contains("leg") || normalized.contains("squat") ||
           normalized.contains("deadlift") || normalized.contains("rdl") ||
           normalized.contains("lunge") || normalized.contains("calf") ||
           normalized.contains("glute") || normalized.contains("hamstring") ||
           normalized.contains("quad") || normalized.contains("hack") ||
           normalized.contains("hip thrust") {
            return .legs
        }

        // BICEPS - specific curl patterns (must check before back to avoid "pulldown" catching curls)
        if normalized.contains("curl") && !normalized.contains("leg") {
            return .biceps
        }
        if normalized.contains("hammer") || normalized.contains("preacher") ||
           normalized.contains("concentration") || normalized.contains("spider curl") ||
           normalized.contains("bicep") {
            return .biceps
        }

        // TRICEPS - specific extension and pushdown patterns
        if normalized.contains("tricep") || normalized.contains("pushdown") ||
           normalized.contains("skullcrusher") || normalized.contains("skull crusher") ||
           (normalized.contains("extension") && !normalized.contains("leg") && !normalized.contains("back")) ||
           normalized.contains("rope extension") {
            return .triceps
        }

        // CHEST - press, bench, fly (must check before shoulders for "press")
        if normalized.contains("bench") || normalized.contains("chest") ||
           normalized.contains("pec") ||
           normalized.contains("fly") || normalized.contains("flye") ||
           normalized.contains("cable cross") {
            return .chest
        }

        // Check for dips (can be chest or triceps - default to chest)
        if normalized.contains("dip") && !normalized.contains("nordic") {
            return .chest
        }

        // SHOULDERS - ohp, raises, shoulder-specific
        if normalized.contains("shoulder") || normalized.contains("ohp") ||
           normalized.contains("overhead press") || normalized.contains("military") ||
           normalized.contains("lateral raise") || normalized.contains("front raise") ||
           normalized.contains("rear delt") || normalized.contains("arnold") ||
           normalized.contains("face pull") || normalized.contains("upright row") ||
           normalized.contains("delt") {
            return .shoulders
        }

        // BACK - rows, pulls, lats
        if normalized.contains("row") || normalized.contains("pulldown") ||
           normalized.contains("pull-down") || normalized.contains("pull up") ||
           normalized.contains("pullup") || normalized.contains("pull-up") ||
           normalized.contains("lat") || normalized.contains("chin") ||
           normalized.contains("back") || normalized.contains("shrug") {
            return .back
        }

        // CORE - abs, planks, core-specific
        if normalized.contains("crunch") || normalized.contains("plank") ||
           normalized.contains(" ab ") || normalized.contains("abs") ||
           normalized.contains("core") || normalized.contains("sit up") ||
           normalized.contains("situp") || normalized.contains("hanging leg") ||
           normalized.contains("wheel") || normalized.contains("pallof") ||
           normalized.contains("woodchop") || normalized.contains("russian twist") {
            return .core
        }

        // Check for press without specific context - default to chest if flat, shoulders if overhead
        if normalized.contains("press") {
            if normalized.contains("overhead") || normalized.contains("standing") {
                return .shoulders
            }
            return .chest
        }

        // Forearm/grip work goes to biceps (closest category)
        if normalized.contains("wrist") || normalized.contains("forearm") || normalized.contains("grip") {
            return .biceps
        }

        // Default fallback - core is safest for miscellaneous
        return .core
    }

    /// Get all exercises from a list grouped by muscle group
    static func categorize(exercises: [String]) -> [MuscleGroup: [String]] {
        var grouped: [MuscleGroup: [String]] = [:]

        for exercise in exercises {
            let group = classify(exercise)
            grouped[group, default: []].append(exercise)
        }

        // Sort exercises within each category
        for group in grouped.keys {
            grouped[group] = grouped[group]?.sorted()
        }

        return grouped
    }
}
