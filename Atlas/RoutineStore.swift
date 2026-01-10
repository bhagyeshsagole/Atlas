//
//  RoutineStore.swift
//  Atlas
//
//  What this file is:
//  - JSON-backed routine (template) storage for the routine builder and list screens.
//
//  Where it’s used:
//  - Injected as an environment object in `AtlasApp` and read/written by routine views.
//  - Saves to `routines.json` in the app Documents directory unless a custom URL is injected (tests).
//
//  Called from:
//  - Used by `RoutineListView`, `CreateRoutineView`, `ReviewRoutineView`, `EditRoutineView`, and `RoutinePreStartView` via environment injection.
//
//  Key concepts:
//  - Uses `Codable` structs to turn routine data into JSON on disk.
//  - `@Published` array notifies SwiftUI views whenever routines change.
//
//  Safe to change:
//  - Add new fields to `Routine`/`RoutineWorkout` (with migration defaults), adjust file name/location if you also update load/save.
//
//  NOT safe to change:
//  - Removing fields without a migration plan; it will break decoding of existing user data.
//  - How `fileURL` resolves the Documents directory; altering without care can orphan user files.
//
//  Common bugs / gotchas:
//  - Forgetting to call `save()` after edits will drop changes on app quit.
//  - Changing `filename` without moving old data will make existing routines disappear.
//
//  DEV MAP:
//  - See: DEV_MAP.md → B) Routines (templates)
//
// FLOW SUMMARY:
// Routine views read/write RoutineStore → store serializes routines to routines.json → on app start, `load()` hydrates the in-memory list for the UI.
//

import Foundation
import Combine

struct Routine: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var workouts: [RoutineWorkout]
    var summary: String
    var source: RoutineSource
    var coachPlanId: UUID?
    var expiresOnCompletion: Bool
    var generatedForRange: StatsLens?

    /// DEV MAP: Routine data model; persisted via JSON in RoutineStore.
    init(
        id: UUID,
        name: String,
        createdAt: Date,
        workouts: [RoutineWorkout],
        summary: String = "",
        source: RoutineSource = .user,
        coachPlanId: UUID? = nil,
        expiresOnCompletion: Bool = false,
        generatedForRange: StatsLens? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.workouts = workouts
        self.summary = summary
        self.source = source
        self.coachPlanId = coachPlanId
        self.expiresOnCompletion = expiresOnCompletion
        self.generatedForRange = generatedForRange
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case workouts
        case summary
        case source
        case coachPlanId
        case expiresOnCompletion
        case generatedForRange
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        workouts = try container.decode([RoutineWorkout].self, forKey: .workouts)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        source = try container.decodeIfPresent(RoutineSource.self, forKey: .source) ?? .user
        coachPlanId = try container.decodeIfPresent(UUID.self, forKey: .coachPlanId)
        expiresOnCompletion = try container.decodeIfPresent(Bool.self, forKey: .expiresOnCompletion) ?? false
        generatedForRange = try container.decodeIfPresent(StatsLens.self, forKey: .generatedForRange)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(summary, forKey: .summary)
        try container.encode(source, forKey: .source)
        try container.encode(coachPlanId, forKey: .coachPlanId)
        try container.encode(expiresOnCompletion, forKey: .expiresOnCompletion)
        try container.encode(generatedForRange, forKey: .generatedForRange)
    }
}

struct RoutineWorkout: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    var wtsText: String
    var repsText: String
}

enum RoutineSource: String, Codable, Hashable {
    case user
    case coach
}

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [Routine] = [] // Live in-memory list that drives routine UI.
    private let filename = "routines.json"
    private let customStorageURL: URL?

    init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL // Tests can inject a sandboxed path to avoid touching real user data.
    }

    /// VISUAL TWEAK: Change the filename or directory here to affect which routine file the UI reads.
    /// VISUAL TWEAK: Change storage location here to adjust how routines persist.
    private var fileURL: URL {
        if let customStorageURL {
            return customStorageURL
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        // If Documents is unavailable (rare), fall back to temp to avoid crashing file writes.
        return (documents ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(filename)
    }

    /// VISUAL TWEAK: Change how initial data populates here to affect what appears in the Routine UI by default.
    /// VISUAL TWEAK: Change decoding/encoding strategy here to adjust how routines persist.
    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Routine].self, from: data)
            routines = decoded
        } catch {
            print("RoutineStore load error: \(error)")
        }
    }

    /// VISUAL TWEAK: Change when this save runs to affect how quickly UI updates reflect persistence.
    /// VISUAL TWEAK: Change the encoder settings here to adjust how routines persist.
    func save() {
        do {
            let data = try JSONEncoder().encode(routines)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("RoutineStore save error: \(error)")
        }
    }

    /// VISUAL TWEAK: Change insertion ordering here to affect how new routines surface in the list.
    /// VISUAL TWEAK: Change persistence timing here to adjust how routines persist.
    func addRoutine(_ routine: Routine) {
        routines.insert(routine, at: 0)
        save()
    }

    /// VISUAL TWEAK: Change deletion filters here to affect which routines disappear from the UI.
    /// VISUAL TWEAK: Change save timing here to adjust how routines persist.
    func deleteRoutine(id: UUID) {
        routines.removeAll { $0.id == id }
        save()
    }

    /// VISUAL TWEAK: Change which fields update here to affect how edits reflect in the preview UI.
    /// VISUAL TWEAK: Change mutation order here to adjust how routines persist.
    func updateWorkoutTexts(routineId: UUID, workoutId: UUID, wts: String?, reps: String?) {
        guard let routineIndex = routines.firstIndex(where: { $0.id == routineId }) else { return }
        guard let workoutIndex = routines[routineIndex].workouts.firstIndex(where: { $0.id == workoutId }) else { return }

        if let wts {
            routines[routineIndex].workouts[workoutIndex].wtsText = wts
        }
        if let reps {
            routines[routineIndex].workouts[workoutIndex].repsText = reps
        }
        save()
    }

    /// VISUAL TWEAK: Change which fields are updatable to control what the Edit screen can save.
    func updateRoutine(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        save()
    }
}
