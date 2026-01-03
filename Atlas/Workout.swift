//
//  Workout.swift
//  Atlas
//
//  Overview: SwiftData model representing a completed workout date.
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
