import Foundation
import AVFoundation
import UserNotifications
import AudioToolbox

enum RestTimerNotifier {
    private static let notificationId = "atlas.resttimer.done"
    private static var audioPlayer: AVAudioPlayer?
    private static var didRequestAuth = false

    static func scheduleNotification(in seconds: Int) {
        guard seconds > 0 else { return }
        requestNotificationAuthIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Timer Done"
        content.body = "Rest complete."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("[TIMER][NOTIFY] schedule failed: \(error.localizedDescription)")
            } else {
                print("[TIMER][NOTIFY] scheduled in \(seconds)s")
            }
            #endif
        }
    }

    static func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
        #if DEBUG
        print("[TIMER][NOTIFY] pending cleared")
        #endif
    }

    static func playCompletion() {
        playSound()
        RestTimerHaptics.playCompletionPattern()
        #if DEBUG
        print("[TIMER][ALERT] completion fired (sound + haptic)")
        #endif
    }

    static func stopCompletion() {
        audioPlayer?.stop()
        audioPlayer = nil
        #if DEBUG
        print("[TIMER][ALERT] stopped playback")
        #endif
    }

    private static func playSound() {
        // Use a short system alert sound; avoids bundling new assets.
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    private static func requestNotificationAuthIfNeeded() {
        guard didRequestAuth == false else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            #if DEBUG
            if let error {
                print("[TIMER][NOTIFY] auth error: \(error.localizedDescription)")
            } else {
                print("[TIMER][NOTIFY] auth granted=\(granted)")
            }
            #endif
        }
    }
}
