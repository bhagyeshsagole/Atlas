import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

enum RestTimerLiveActivityController {
    static func start(endsAt: Date, exerciseName: String?) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RestTimerAttributes(exerciseName: exerciseName)
        let state = RestTimerAttributes.ContentState(endsAt: endsAt)
        Task {
            do {
                currentActivity = try Activity.request(attributes: attributes, contentState: state)
                #if DEBUG
                print("[TIMER][LIVE] started endsAt=\\(endsAt)")
                #endif
            } catch {
                #if DEBUG
                print("[TIMER][LIVE] start failed: \\(error.localizedDescription)")
                #endif
            }
        }
        #endif
    }

    static func end() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        Task {
            if let activity = currentActivity {
                await activity.end(dismissalPolicy: .immediate)
                #if DEBUG
                print("[TIMER][LIVE] ended")
                #endif
            }
            currentActivity = nil
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static var currentActivity: Activity<RestTimerAttributes>?
    #endif
}
