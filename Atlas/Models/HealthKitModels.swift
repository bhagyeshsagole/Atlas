//
//  HealthKitModels.swift
//  Atlas
//
//  What this file is:
//  - SwiftData models for caching HealthKit cardio workouts locally.
//
//  Where it's used:
//  - Cached by `HealthKitStore` and displayed in `StatsView`.
//
//  Called from:
//  - Referenced in `AtlasApp.modelTypes` and used by HealthKitStore for offline access.
//
//  Key concepts:
//  - `@Model` marks types that SwiftData persists automatically.
//  - Caching enables offline access to previously-fetched HealthKit data.
//
//  Safe to change:
//  - Add optional fields for new metrics (with defaults) while handling migrations.
//
//  NOT safe to change:
//  - Removing properties or changing types without migration; users could lose cached data.
//  - The `workoutId` unique identifier which prevents duplicates.
//
//  Common bugs / gotchas:
//  - Storing distance/duration without units can cause confusion; document units clearly.
//
//  DEV MAP:
//  - See: DEV_MAP.md → F) HealthKit Integration
//

import Foundation
import SwiftData

/// Cached HealthKit cardio workout for offline Stats display.
/// Distances in meters, durations in seconds, energy in kcal.
@Model
final class HealthWorkoutCache {
    @Attribute(.unique) var workoutId: String // HKWorkout UUID
    var activityType: String
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var activeEnergyKcal: Double?
    var avgHeartRate: Double?
    var sourceName: String?
    var lastSyncedAt: Date

    init(
        workoutId: String,
        activityType: String,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKcal: Double? = nil,
        avgHeartRate: Double? = nil,
        sourceName: String? = nil,
        lastSyncedAt: Date = Date()
    ) {
        self.workoutId = workoutId
        self.activityType = activityType
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate
        self.sourceName = sourceName
        self.lastSyncedAt = lastSyncedAt
    }
}
