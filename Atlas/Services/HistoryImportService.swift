//
//  HistoryImportService.swift
//  Atlas
//
//  What this file is:
//  - AI-powered service for importing workout history from text logs.
//
//  Where it's used:
//  - Called from ImportHistoryView when user pastes or uploads workout logs.
//
//  Key concepts:
//  - Uses OpenAI via EdgeFunctionClient to parse messy workout logs into structured data.
//  - Supports mixed units, missing data, and various log formats.
//  - Implements idempotency to avoid duplicate imports (checks by date + routine title).
//
//  Safe to change:
//  - AI prompt refinement for better parsing accuracy.
//  - Validation rules for imported data.
//
//  NOT safe to change:
//  - ImportedSession structure without updating consumers.
//  - Idempotency logic without careful testing.
//

import Foundation
import SwiftData

/// Represents a parsed workout session before import
struct ImportedSession: Identifiable, Codable, Equatable {
    let id: UUID
    let routineTitle: String
    let date: Date
    let durationMinutes: Int?
    let exercises: [ImportedExercise]
    var isValid: Bool {
        !routineTitle.isEmpty && !exercises.isEmpty
    }

    init(id: UUID = UUID(), routineTitle: String, date: Date, durationMinutes: Int?, exercises: [ImportedExercise]) {
        self.id = id
        self.routineTitle = routineTitle
        self.date = date
        self.durationMinutes = durationMinutes
        self.exercises = exercises
    }
}

struct ImportedExercise: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let sets: [ImportedSet]

    init(id: UUID = UUID(), name: String, sets: [ImportedSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

struct ImportedSet: Identifiable, Codable, Equatable {
    let id: UUID
    let weightValue: Double?
    let weightUnit: String // "kg" or "lb"
    let reps: Int
    let tag: String // "W", "S", or "DS"

    init(id: UUID = UUID(), weightValue: Double?, weightUnit: String, reps: Int, tag: String = "S") {
        self.id = id
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.reps = reps
        self.tag = tag
    }
}

enum HistoryImportError: LocalizedError {
    case emptyInput
    case parsingFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No workout log text provided."
        case .parsingFailed(let message):
            return "Failed to parse workout log: \(message)"
        case .importFailed(let message):
            return "Failed to import workouts: \(message)"
        }
    }
}

@MainActor
final class HistoryImportService {

    /// Parse workout history text using AI
    static func parseWorkoutHistory(rawText: String) async throws -> [ImportedSession] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HistoryImportError.emptyInput
        }

        let prompt = buildParsingPrompt(rawText: trimmed)

        #if DEBUG
        print("[IMPORT] Parsing workout history via AI...")
        #endif

        let responseText = try await OpenAIChatClient.chat(prompt: prompt)

        // Parse JSON response
        guard let data = responseText.data(using: .utf8) else {
            throw HistoryImportError.parsingFailed("Unable to encode AI response.")
        }

        let decoder = JSONDecoder()
        // Custom date decoding: YYYY-MM-DD string → local timezone start of day
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try YYYY-MM-DD format first (our expected format)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = .current  // Use user's local timezone
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")

            if let date = dateFormatter.date(from: dateString) {
                // Return start of day in local timezone to preserve the intended date
                return Calendar.current.startOfDay(for: date)
            }

            // Fallback: try ISO8601 with time if YYYY-MM-DD fails
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                // Normalize to start of day in local timezone
                return Calendar.current.startOfDay(for: date)
            }

            // Try ISO8601 without fractional seconds
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return Calendar.current.startOfDay(for: date)
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        do {
            let parsed = try decoder.decode(ParsedWorkoutHistory.self, from: data)

            // Convert to ImportedSession array
            let sessions = parsed.sessions.map { parsedSession in
                let exercises = parsedSession.exercises.map { parsedExercise in
                    let sets = parsedExercise.sets.map { parsedSet in
                        ImportedSet(
                            weightValue: parsedSet.weight,
                            weightUnit: parsedSet.unit,
                            reps: parsedSet.reps,
                            tag: parsedSet.tag
                        )
                    }
                    return ImportedExercise(name: parsedExercise.name, sets: sets)
                }

                // Date is already normalized to local timezone start of day by decoder
                return ImportedSession(
                    routineTitle: parsedSession.title,
                    date: parsedSession.date,
                    durationMinutes: parsedSession.durationMinutes,
                    exercises: exercises
                )
            }

            #if DEBUG
            print("[IMPORT] Parsed \(sessions.count) workout sessions")
            #endif

            return sessions
        } catch {
            throw HistoryImportError.parsingFailed("Invalid JSON format: \(error.localizedDescription)")
        }
    }

    /// Import parsed sessions to SwiftData with idempotency check
    static func importSessions(_ sessions: [ImportedSession], to context: ModelContext) throws -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0

        for session in sessions where session.isValid {
            // Idempotency check: skip if session with same title and date already exists
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: session.date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? session.date

            let descriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { workoutSession in
                    workoutSession.routineTitle == session.routineTitle &&
                    workoutSession.startedAt >= startOfDay &&
                    workoutSession.startedAt < endOfDay
                }
            )

            if let existing = try? context.fetch(descriptor).first, existing.id != session.id {
                #if DEBUG
                print("[IMPORT] Skipping duplicate: \(session.routineTitle) on \(session.date)")
                #endif
                skipped += 1
                continue
            }

            // Calculate totals
            var totalSets = 0
            var totalReps = 0
            var volumeKg: Double = 0

            let exerciseLogs = session.exercises.enumerated().map { index, exercise in
                let setLogs = exercise.sets.map { set in
                    let weightKg: Double?
                    if let weight = set.weightValue {
                        // Convert to kg if needed
                        weightKg = set.weightUnit.lowercased() == "lb" ? weight / WorkoutSessionFormatter.kgToLb : weight
                    } else {
                        weightKg = nil
                    }

                    totalSets += 1
                    totalReps += set.reps
                    if let wkg = weightKg {
                        volumeKg += wkg * Double(set.reps)
                    }

                    let unit: WorkoutUnits = set.weightUnit.lowercased() == "lb" ? .lb : .kg
                    return SetLog(
                        tag: set.tag,
                        weightKg: weightKg,
                        reps: set.reps,
                        enteredUnit: unit,
                        createdAt: session.date
                    )
                }

                return ExerciseLog(
                    name: exercise.name,
                    orderIndex: index,
                    sets: setLogs
                )
            }

            // Create workout session
            let endDate = session.durationMinutes.map { session.date.addingTimeInterval(TimeInterval($0 * 60)) } ?? session.date

            let workoutSession = WorkoutSession(
                id: session.id,
                routineId: nil,
                routineTitle: session.routineTitle,
                startedAt: session.date,
                endedAt: endDate,
                totalSets: totalSets,
                totalReps: totalReps,
                volumeKg: volumeKg,
                isCompleted: true,
                durationSeconds: session.durationMinutes.map { $0 * 60 },
                exercises: exerciseLogs
            )

            context.insert(workoutSession)
            imported += 1

            #if DEBUG
            print("[IMPORT] Imported: \(session.routineTitle) on \(session.date) (\(exerciseLogs.count) exercises, \(totalSets) sets)")
            #endif
        }

        if imported > 0 {
            try context.save()
        }

        return (imported, skipped)
    }

    private static func buildParsingPrompt(rawText: String) -> String {
        // Get current date in YYYY-MM-DD format for default
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])

        return """
You are a workout log parser. Parse the following workout history into structured JSON.

Rules:
- Extract all workout sessions from the text
- Each session should have: title, date (YYYY-MM-DD format only, no time), optional durationMinutes, and exercises
- Each exercise has: name, and an array of sets
- Each set has: weight (number or null), unit ("kg" or "lb"), reps (number), tag ("W" for warmup, "S" for standard, "DS" for drop set - default "S")
- If date is not specified, use today: \(today)
- If duration is not specified, leave as null
- Handle messy formats: mixed units, missing data, various date formats
- Infer workout titles from context if not explicit (e.g., "Push Day", "Leg Day", "Full Body")
- Keep exercise names clean and consistent (Title Case)
- IMPORTANT: Return date as YYYY-MM-DD only (e.g., "2024-01-15"), NOT ISO8601 with time/timezone

Return ONLY valid JSON matching this schema (no markdown, no commentary):
{
  "sessions": [
    {
      "title": "Push Day",
      "date": "2024-01-15",
      "durationMinutes": 75,
      "exercises": [
        {
          "name": "Bench Press",
          "sets": [
            { "weight": 135, "unit": "lb", "reps": 10, "tag": "S" },
            { "weight": 155, "unit": "lb", "reps": 8, "tag": "S" }
          ]
        }
      ]
    }
  ]
}

Workout log text:
\"\"\"
\(rawText)
\"\"\"
"""
    }
}

// MARK: - Internal parsing models

private struct ParsedWorkoutHistory: Codable {
    let sessions: [ParsedSession]
}

private struct ParsedSession: Codable {
    let title: String
    let date: Date
    let durationMinutes: Int?
    let exercises: [ParsedExercise]
}

private struct ParsedExercise: Codable {
    let name: String
    let sets: [ParsedSet]
}

private struct ParsedSet: Codable {
    let weight: Double?
    let unit: String
    let reps: Int
    let tag: String
}
