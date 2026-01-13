//
//  ExerciseMuscleMap.swift
//  Atlas
//
//  What this file is:
//  - Simple lookup that maps exercise names to primary/secondary muscle groups for summaries.
//
//  Where it’s used:
//  - Called by AI summary views to label exercises when AI responses are missing or sparse.
//
//  Called from:
//  - Used inside `RoutineAIService` when constructing fallback summary data for `PostWorkoutSummaryView`.
//
//  Key concepts:
//  - Uses string contains checks to pick a muscle group; runs locally with no network calls.
//
//  Safe to change:
//  - Add new keyword matches or adjust muscle labels to improve summary accuracy.
//
//  NOT safe to change:
//  - Removing keyword coverage without replacing it; summaries could show generic labels.
//
//  Common bugs / gotchas:
//  - Order matters: earlier checks match first; place more specific keywords before generic ones.
//
//  DEV MAP:
//  - See: DEV_MAP.md → Post-Workout Summary (AI)
//
import Foundation

/// VISUAL TWEAK: To change muscle labels shown in Summary, edit `ExerciseMuscleMap` keywords.
/// DEV NOTE: Keep this deterministic (no network) so Summary can render even if AI fails.
enum ExerciseMuscleMap {
    static func muscles(for name: String) -> (primary: String, secondary: String) {
        // Legacy/general labels used by coverage scoring and summaries.
        let lower = name.lowercased()
        if lower.contains("bench") || lower.contains("press") {
            return ("Chest", "Triceps · Front delts")
        }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull-up") || lower.contains("pull up") {
            return ("Lats", "Mid-back · Biceps")
        }
        if lower.contains("squat") || lower.contains("leg press") {
            return ("Quads", "Glutes")
        }
        if lower.contains("deadlift") || lower.contains("hinge") || lower.contains("rdl") {
            return ("Hamstrings", "Glutes · Lower back")
        }
        if lower.contains("curl") {
            return ("Biceps", "Forearms")
        }
        if lower.contains("extension") || lower.contains("pushdown") || lower.contains("pressdown") || lower.contains("tricep") {
            return ("Triceps", "Elbow extensors")
        }
        if lower.contains("lateral") && lower.contains("raise") {
            return ("Lateral delts", "Shoulders")
        }
        if lower.contains("shrug") {
            return ("Traps", "Upper back")
        }
        if lower.contains("hip thrust") || lower.contains("glute bridge") {
            return ("Glutes", "Hamstrings")
        }
        if lower.contains("lunge") || lower.contains("split squat") {
            return ("Quads", "Glutes · Adductors")
        }
        if lower.contains("calf") {
            return ("Calves", "—")
        }
        if lower.contains("core") || lower.contains("plank") || lower.contains("pallof") {
            return ("Core", "Obliques")
        }
        return ("General", "—")
    }

    static func detailedMuscles(for name: String) -> (primary: [String], secondary: [String]) {
        let lower = name.lowercased()

        func entry(primary: [String], secondary: [String]) -> (primary: [String], secondary: [String]) {
            (primary, secondary)
        }

        if lower.contains("bench") || lower.contains("press") {
            return entry(primary: ["Pectoralis major"], secondary: ["Triceps brachii", "Anterior deltoid"])
        }
        if lower.contains("overhead") || lower.contains("ohp") || lower.contains("shoulder press") {
            return entry(primary: ["Deltoid (anterior)"], secondary: ["Triceps brachii", "Upper trapezius"])
        }
        if lower.contains("row") || lower.contains("pulldown") || lower.contains("pull-up") || lower.contains("pull up") {
            return entry(primary: ["Latissimus dorsi"], secondary: ["Rhomboids", "Biceps brachii", "Posterior deltoid"])
        }
        if lower.contains("squat") || lower.contains("leg press") || lower.contains("hack squat") {
            return entry(primary: ["Quadriceps"], secondary: ["Gluteus maximus", "Erector spinae"])
        }
        if lower.contains("deadlift") || lower.contains("hinge") || lower.contains("rdl") {
            return entry(primary: ["Hamstrings"], secondary: ["Gluteus maximus", "Erector spinae"])
        }
        if lower.contains("lunge") || lower.contains("split squat") {
            return entry(primary: ["Quadriceps"], secondary: ["Gluteus maximus", "Adductors"])
        }
        if lower.contains("hip thrust") || lower.contains("glute bridge") {
            return entry(primary: ["Gluteus maximus"], secondary: ["Hamstrings"])
        }
        if lower.contains("curl") {
            return entry(primary: ["Biceps brachii"], secondary: ["Brachialis", "Forearm flexors"])
        }
        if lower.contains("extension") || lower.contains("pushdown") || lower.contains("pressdown") || lower.contains("tricep") {
            return entry(primary: ["Triceps brachii"], secondary: ["Anconeus"])
        }
        if lower.contains("lateral") && lower.contains("raise") {
            return entry(primary: ["Deltoid (lateral)"], secondary: ["Supraspinatus"])
        }
        if lower.contains("face pull") || lower.contains("rear delt") {
            return entry(primary: ["Deltoid (posterior)"], secondary: ["Rhomboids", "Lower trapezius"])
        }
        if lower.contains("shrug") {
            return entry(primary: ["Upper trapezius"], secondary: ["Levator scapulae"])
        }
        if lower.contains("calf") {
            return entry(primary: ["Gastrocnemius", "Soleus"], secondary: [])
        }
        if lower.contains("core") || lower.contains("plank") || lower.contains("pallof") {
            return entry(primary: ["Rectus abdominis", "Obliques"], secondary: ["Transversus abdominis"])
        }
        return entry(primary: [], secondary: [])
    }
}
