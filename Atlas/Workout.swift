//
//  Workout.swift
//  Atlas
//
//  What this file is:
//  - SwiftData model representing a completed workout date for calendar marks.
//
//  Where it’s used:
//  - Queried in `HomeView` to underline days on the calendar.
//
//  Called from:
//  - Inserted in `WorkoutView` and referenced by `HomeView` `@Query`; listed in `AtlasApp` modelTypes.
//
//  Key concepts:
//  - Minimal `@Model` with a single `Date` property stored in SwiftData.
//
//  Safe to change:
//  - Add optional metadata if you also migrate data and update queries.
//
//  NOT safe to change:
//  - Removing or altering the `date` property without handling migrations; calendar marks rely on it.
//
//  Common bugs / gotchas:
//  - Storing non-normalized dates can lead to duplicate marks; normalize to start-of-day when saving.
//
//  DEV MAP:
//  - See: DEV_MAP.md → A) App Entry + Navigation
//

import Foundation
import SwiftData

@Model
final class Workout {
    /// Stores the date for a completed workout.
    /// Change impact: Altering stored properties changes how workouts are persisted and displayed on the calendar.
    var date: Date

    /// Creates a new workout on a given date.
    /// Change impact: Changing default date handling affects how dates normalize onto the calendar grid.
    init(date: Date) {
        self.date = date
    }
}
