import SwiftUI
import Combine

/// Local username state + prompt dismissal flags. Persists to UserDefaults via AppStorage.
final class UsernameStore: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()

    @AppStorage("atlas.username") var username: String = "" {
        didSet { objectWillChange.send() }
    }

    @AppStorage("atlas.usernamePromptDismissed") var dismissedPrompt: Bool = false {
        didSet { objectWillChange.send() }
    }

    var hasUsername: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func shouldPrompt(remoteUsername: String?) -> Bool {
        dismissedPrompt == false && hasUsername == false && (remoteUsername?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
