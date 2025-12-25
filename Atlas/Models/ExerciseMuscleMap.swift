import Foundation

/// VISUAL TWEAK: To change muscle labels shown in Summary, edit `ExerciseMuscleMap` keywords.
/// DEV NOTE: Keep this deterministic (no network) so Summary can render even if AI fails.
enum ExerciseMuscleMap {
    static func muscles(for name: String) -> (primary: String, secondary: String) {
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
        if lower.contains("deadlift") || lower.contains("hinge") {
            return ("Hamstrings", "Glutes · Lower back")
        }
        if lower.contains("curl") {
            return ("Biceps", "Forearms")
        }
        if lower.contains("extension") || lower.contains("pushdown") {
            return ("Triceps", "Elbow extensors")
        }
        if lower.contains("lateral") && lower.contains("raise") {
            return ("Lateral delts", "Shoulders")
        }
        if lower.contains("shrug") {
            return ("Traps", "Upper back")
        }
        return ("General", "—")
    }
}
