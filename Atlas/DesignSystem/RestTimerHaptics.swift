import Foundation
import CoreHaptics
import UIKit

enum RestTimerHaptics {
    static func playCompletionPattern() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            playCoreHapticsPattern()
        } else {
            playFallbackPattern()
        }
    }

    private static func playCoreHapticsPattern() {
        do {
            let engine = try CHHapticEngine()
            try engine.start()
            var events: [CHHapticEvent] = []
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.75)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0, duration: 0.15)
            events.append(event)

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            engine.notifyWhenPlayersFinished { _ in
                engine.stop(completionHandler: nil)
                return .stopEngine
            }
        } catch {
            playFallbackPattern()
        }
    }

    private static func playFallbackPattern() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
}
