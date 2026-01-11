import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endsAt: Date
        public init(endsAt: Date) {
            self.endsAt = endsAt
        }
    }

    public var exerciseName: String?

    public init(exerciseName: String? = nil) {
        self.exerciseName = exerciseName
    }
}
#endif
