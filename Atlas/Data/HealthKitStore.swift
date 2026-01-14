//
//  HealthKitStore.swift
//  Atlas
//
//  What this file is:
//  - HealthKit integration for importing cardio workouts from Apple Health.
//
//  Where it's used:
//  - Injected as an environment object and used by StatsView to display cardio data.
//
//  Called from:
//  - Stats tab for displaying cardio metrics alongside lifting stats.
//
//  Key concepts:
//  - Read-only HealthKit access (no writing to Health).
//  - Fetches HKWorkout objects for cardio activities (Run/Walk/Cycle/Swim/etc).
//  - Caches workouts in SwiftData for offline access.
//
//  Safe to change:
//  - Add more activity types to fetch, adjust date range queries.
//
//  NOT safe to change:
//  - Authorization flow without user testing; HealthKit denials need graceful handling.
//  - Cache invalidation logic without considering offline scenarios.
//
//  Common bugs / gotchas:
//  - HealthKit is not available in Simulator; requires real device for testing.
//  - Authorization must be requested before any queries.
//
//  DEV MAP:
//  - See: DEV_MAP.md → F) HealthKit Integration
//

import Foundation
import Combine
import HealthKit
import SwiftData

@MainActor
final class HealthKitStore: ObservableObject {
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    private let healthStore: HKHealthStore?
    private let modelContext: ModelContext?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        // HealthKit is only available on iOS devices, not in Simulator
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
            checkAuthorizationStatus()
        } else {
            self.healthStore = nil
            #if DEBUG
            print("[HealthKit] Health data not available on this device")
            #endif
        }
    }

    private func checkAuthorizationStatus() {
        guard let healthStore else {
            authorizationStatus = .notDetermined
            isAuthorized = false
            return
        }

        // Check authorization for workout type
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        authorizationStatus = status
        isAuthorized = (status == .sharingAuthorized)
    }

    func requestAuthorization() async throws {
        guard let healthStore else {
            throw HealthKitError.notAvailable
        }

        // Define the types we want to read
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            checkAuthorizationStatus()
            #if DEBUG
            print("[HealthKit] Authorization requested, status: \(authorizationStatus.rawValue)")
            #endif
        } catch {
            #if DEBUG
            print("[HealthKit] Authorization failed: \(error)")
            #endif
            throw HealthKitError.authorizationFailed(error)
        }
    }

    func fetchWorkoutsWithCache(from startDate: Date, to endDate: Date) async throws -> [HealthWorkoutSummary] {
        // Try cache first
        if let cached = try? fetchFromCache(from: startDate, to: endDate), !cached.isEmpty {
            #if DEBUG
            print("[HealthKit] Using cached workouts: \(cached.count)")
            #endif
            return cached
        }

        // Fetch from HealthKit and cache
        let workouts = try await fetchWorkouts(from: startDate, to: endDate)
        cacheWorkouts(workouts)
        return workouts
    }

    func fetchWorkouts(from startDate: Date, to endDate: Date) async throws -> [HealthWorkoutSummary] {
        guard let healthStore else {
            throw HealthKitError.notAvailable
        }

        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let summaries = workouts.compactMap { workout -> HealthWorkoutSummary? in
                    // Filter to cardio-type workouts only
                    guard self.isCardioWorkout(workout.workoutActivityType) else {
                        return nil
                    }

                    return HealthWorkoutSummary(
                        id: workout.uuid.uuidString,
                        activityType: self.activityTypeName(workout.workoutActivityType),
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                        activeEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        sourceName: workout.sourceRevision.source.name
                    )
                }

                #if DEBUG
                print("[HealthKit] Fetched \(summaries.count) cardio workouts from \(startDate) to \(endDate)")
                #endif

                continuation.resume(returning: summaries)
            }

            healthStore.execute(query)
        }
    }

    private func fetchFromCache(from startDate: Date, to endDate: Date) throws -> [HealthWorkoutSummary] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<HealthWorkoutCache>(
            predicate: #Predicate { workout in
                workout.startDate >= startDate && workout.startDate <= endDate
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let cached = try modelContext.fetch(descriptor)
        return cached.map { cache in
            HealthWorkoutSummary(
                id: cache.workoutId,
                activityType: cache.activityType,
                startDate: cache.startDate,
                endDate: cache.endDate,
                duration: cache.durationSeconds,
                distanceMeters: cache.distanceMeters,
                activeEnergyKcal: cache.activeEnergyKcal,
                sourceName: cache.sourceName
            )
        }
    }

    private func cacheWorkouts(_ workouts: [HealthWorkoutSummary]) {
        guard let modelContext else { return }

        for workout in workouts {
            // Check if already cached
            let workoutId = workout.id
            let descriptor = FetchDescriptor<HealthWorkoutCache>(
                predicate: #Predicate { $0.workoutId == workoutId }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                // Update existing
                existing.activityType = workout.activityType
                existing.startDate = workout.startDate
                existing.endDate = workout.endDate
                existing.durationSeconds = workout.duration
                existing.distanceMeters = workout.distanceMeters
                existing.activeEnergyKcal = workout.activeEnergyKcal
                existing.sourceName = workout.sourceName
                existing.lastSyncedAt = Date()
            } else {
                // Insert new
                let cache = HealthWorkoutCache(
                    workoutId: workout.id,
                    activityType: workout.activityType,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationSeconds: workout.duration,
                    distanceMeters: workout.distanceMeters,
                    activeEnergyKcal: workout.activeEnergyKcal,
                    sourceName: workout.sourceName
                )
                modelContext.insert(cache)
            }
        }

        try? modelContext.save()

        #if DEBUG
        print("[HealthKit] Cached \(workouts.count) workouts")
        #endif
    }

    private func isCardioWorkout(_ type: HKWorkoutActivityType) -> Bool {
        switch type {
        case .running, .walking, .cycling, .swimming, .rowing,
             .elliptical, .stairClimbing, .functionalStrengthTraining,
             .hiking, .dance, .yoga, .jumpRope, .barre,
             .coreTraining, .crossTraining, .mixedCardio,
             .paddleSports, .skatingSports, .snowSports, .waterSports:
            return true
        default:
            return false
        }
    }

    private func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .hiking: return "Hiking"
        case .dance: return "Dance"
        case .yoga: return "Yoga"
        case .jumpRope: return "Jump Rope"
        case .barre: return "Barre"
        case .coreTraining: return "Core Training"
        case .crossTraining: return "Cross Training"
        case .functionalStrengthTraining: return "Functional Training"
        case .mixedCardio: return "Mixed Cardio"
        case .paddleSports: return "Paddle Sports"
        case .skatingSports: return "Skating"
        case .snowSports: return "Snow Sports"
        case .waterSports: return "Water Sports"
        default: return "Cardio"
        }
    }
}

struct HealthWorkoutSummary: Identifiable, Hashable {
    let id: String
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let sourceName: String?

    var durationMinutes: Int {
        Int(duration / 60)
    }

    var distanceKm: Double? {
        guard let meters = distanceMeters else { return nil }
        return meters / 1000.0
    }

    var distanceMiles: Double? {
        guard let meters = distanceMeters else { return nil }
        return meters * 0.000621371
    }
}

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case authorizationFailed(Error)
    case queryFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .notAuthorized:
            return "HealthKit access not authorized. Please enable in Settings."
        case .authorizationFailed(let error):
            return "HealthKit authorization failed: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "HealthKit query failed: \(error.localizedDescription)"
        }
    }
}
