import ActivityKit
import WidgetKit
import SwiftUI

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text("Rest")
                    .font(.headline)
                if let name = context.attributes.exerciseName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.title2.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Rest")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                        .font(.title2.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    if let name = context.attributes.exerciseName {
                        Text(name)
                            .font(.subheadline)
                    }
                }
            } compactLeading: {
                Text("Rest")
                    .font(.caption)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

@main
struct RestTimerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
