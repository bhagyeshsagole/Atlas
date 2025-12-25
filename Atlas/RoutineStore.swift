//
//  RoutineStore.swift
//  Atlas
//
//  Created by Codex on 2/20/24.
//
//  Update: Hardening pass to support custom storage URLs for tests without changing runtime behavior.

import Foundation
import Combine

struct Routine: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var workouts: [RoutineWorkout]
    var summary: String

    /// DEV MAP: Routine data model; persisted via JSON in RoutineStore.
    init(id: UUID, name: String, createdAt: Date, workouts: [RoutineWorkout], summary: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.workouts = workouts
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case workouts
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        workouts = try container.decode([RoutineWorkout].self, forKey: .workouts)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(summary, forKey: .summary)
    }
}

struct RoutineWorkout: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    var wtsText: String
    var repsText: String
}

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [Routine] = []
    private let filename = "routines.json"
    private let customStorageURL: URL?

    init(storageURL: URL? = nil) {
        self.customStorageURL = storageURL
    }

    /// VISUAL TWEAK: Change the filename or directory here to affect which routine file the UI reads.
    /// VISUAL TWEAK: Change storage location here to adjust how routines persist.
    private var fileURL: URL {
        if let customStorageURL {
            return customStorageURL
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
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
