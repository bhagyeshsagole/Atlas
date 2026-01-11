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
            let pulseCount = 5
            let interval: TimeInterval = 0.25

            for i in 0..<pulseCount {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(0.75 + (Double(i) / Double(pulseCount)) * 0.15))
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: Double(i) * interval, duration: 0.1)
                events.append(event)
            }

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
        let pulses = 5
        let interval: TimeInterval = 0.25
        for i in 0..<pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * interval)) {
                generator.impactOccurred()
            }
        }
    }
}
