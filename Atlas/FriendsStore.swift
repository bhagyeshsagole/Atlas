import Foundation
import Combine
import Supabase

@MainActor
final class FriendsStore: ObservableObject {
    @Published var friends: [AtlasFriend] = []
    @Published var incomingRequests: [AtlasFriendRequest] = []
    @Published var outgoingRequests: [AtlasFriendRequest] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var uiError: String?
    @Published var lastErrorMessage: String?
    @Published var successMessage: String?
    @Published var refreshToken = UUID()

    private let authStore: AuthStore
    private var didStartForUser: UUID?
    private var isRefreshing = false
    private var isSending = false
    private var isResponding = false
    private var isRemoving = false

    init(authStore: AuthStore) {
        self.authStore = authStore
    }

    func startIfNeeded() async {
        guard let (_, userId) = resolveServiceAndUser(action: "start") else { return }
        if didStartForUser != userId {
            didStartForUser = userId
            await refreshAll()
        }
    }

    func refreshAll() async {
        guard let (service, userId) = resolveServiceAndUser(action: "refresh") else { return }
        guard isRefreshing == false else { return }
        isRefreshing = true
        didStartForUser = userId
        updateLoadingState()
        do {
            async let friendsTask = service.fetchFriends(for: userId)
            async let incomingTask = service.fetchIncomingRequests(for: userId)
            async let outgoingTask = service.fetchOutgoingRequests(for: userId)
            let newFriends = try await friendsTask
            let newIncoming = try await incomingTask
            let newOutgoing = try await outgoingTask
            await MainActor.run {
                friends = newFriends
                incomingRequests = newIncoming
                outgoingRequests = newOutgoing
                errorMessage = nil
                uiError = nil
                lastErrorMessage = nil
                refreshToken = UUID()
            }
            log("refresh incoming=\(newIncoming.count) outgoing=\(newOutgoing.count) friends=\(newFriends.count)")
        } catch {
            handle(error)
            log("refreshAll failed user=\(userId) error=\(error.localizedDescription)")
        }
        isRefreshing = false
        updateLoadingState()
    }

    func sendRequest(username: String) async {
        guard isSending == false else { return }
        guard let (service, userId) = resolveServiceAndUser(action: "send") else { return }
        isSending = true
        await MainActor.run {
            errorMessage = nil
            uiError = nil
            lastErrorMessage = nil
            successMessage = nil
        }
        updateLoadingState()
        defer {
            isSending = false
            updateLoadingState()
        }
        do {
            try await service.sendFriendRequest(input: username)
            log("send success user=\(userId) username=\(username)")
            await refreshAll()
            await showSuccess("Friend request sent.")
        } catch {
            handle(error)
            log("send failed user=\(userId) username=\(username) error=\(error.localizedDescription)")
        }
    }

    func accept(requestIdString: String) async {
        guard let requestId = UUID(uuidString: requestIdString) else {
            lastErrorMessage = "Invalid request id."
            return
        }
        guard isResponding == false else { return }
        guard let (service, userId) = resolveServiceAndUser(action: "accept") else { return }
        isResponding = true
        await MainActor.run {
            errorMessage = nil
            uiError = nil
            lastErrorMessage = nil
            successMessage = nil
        }
        updateLoadingState()
        defer {
            isResponding = false
            updateLoadingState()
        }
        do {
            try await service.acceptRequest(requestId: requestId)
            await refreshAll()
            await showSuccess("Request accepted.")
            log("accept success user=\(userId) requestId=\(requestId)")
        } catch {
            handle(error)
            log("accept failed user=\(userId) requestId=\(requestId) error=\(error.localizedDescription)")
        }
    }

    func decline(requestIdString: String) async {
        guard let requestId = UUID(uuidString: requestIdString) else {
            lastErrorMessage = "Invalid request id."
            return
        }
        guard isResponding == false else { return }
        guard let (service, userId) = resolveServiceAndUser(action: "decline") else { return }
        isResponding = true
        await MainActor.run {
            errorMessage = nil
            uiError = nil
            lastErrorMessage = nil
            successMessage = nil
        }
        updateLoadingState()
        defer {
            isResponding = false
            updateLoadingState()
        }
        do {
            try await service.declineRequest(requestId: requestId)
            await refreshAll()
            await showSuccess("Request declined.")
            log("decline success user=\(userId) requestId=\(requestId)")
        } catch {
            handle(error)
            log("decline failed user=\(userId) requestId=\(requestId) error=\(error.localizedDescription)")
        }
    }

    func remove(friendIdString: String) async -> Bool {
        guard let friendId = UUID(uuidString: friendIdString) else {
            lastErrorMessage = "Invalid friend id."
            return false
        }
        guard isRemoving == false else { return false }
        guard let (service, userId) = resolveServiceAndUser(action: "remove") else { return false }
        isRemoving = true
        await MainActor.run {
            errorMessage = nil
            uiError = nil
            lastErrorMessage = nil
            successMessage = nil
        }
        updateLoadingState()
        defer {
            isRemoving = false
            updateLoadingState()
        }
        do {
            try await service.removeFriend(friendId: friendId)
            await refreshAll()
            await showSuccess("Friend removed.")
            log("remove success user=\(userId) friendId=\(friendId)")
            return true
        } catch {
            handle(error)
            log("remove failed user=\(userId) friendId=\(friendId) error=\(error.localizedDescription)")
            return false
        }
    }

    private func currentUserId() -> UUID? {
        if let id = authStore.currentUserId { return id }
        guard let idString = authStore.userId, let id = UUID(uuidString: idString) else { return nil }
        return id
    }

    private func resolveServiceAndUser(action: String) -> (FriendsService, UUID)? {
        guard authStore.isReadyForFriends else {
            let message = "Sign in to use Friends."
            uiError = message
            lastErrorMessage = message
            resetIfLoggedOut()
            log("\(action) blocked (auth not ready)")
            return nil
        }
        guard let client = authStore.supabaseClient else {
            let message = "Supabase not configured."
            uiError = message
            lastErrorMessage = message
            log("\(action) blocked (missing client)")
            return nil
        }
        guard let userId = authStore.currentUserId ?? currentUserId() else {
            let message = "Sign in to use Friends."
            uiError = message
            lastErrorMessage = message
            resetIfLoggedOut()
            log("\(action) blocked (missing user)")
            return nil
        }
        return (FriendsService(client: client), userId)
    }

    private func resetIfLoggedOut() {
        if didStartForUser != nil {
            friends = []
            incomingRequests = []
            outgoingRequests = []
            errorMessage = nil
            uiError = nil
        }
        didStartForUser = nil
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[FRIENDS] \(message)")
        #endif
    }

    private func handle(_ error: Error) {
        let friendly = friendlyMessage(for: error)
        errorMessage = friendly
        lastErrorMessage = friendly
        #if DEBUG
        print("[FRIENDS][ERROR] \(error)")
        #endif
    }

    private func friendlyMessage(for error: Error) -> String {
        if let err = error as? FriendsServiceError {
            switch err {
            case .invalidUsername: return "Enter a valid username."
            case .invalidEmail: return "Enter a valid email."
            case .profileNotFound: return "No user found for that username."
            case .cannotFriendSelf: return "You cannot send a request to yourself."
            case .duplicateRequest, .alreadyFriends: return "Request already sent."
            case .unauthorized: return "Not authorized."
            case .backend(let message): return message
            }
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("correct format") || message.contains("couldn’t be read") || message.contains("couldn't be read") {
            return "Friend request sent."
        }
        return "Something went wrong."
    }

    private func updateLoadingState() {
        isLoading = isRefreshing || isSending || isResponding || isRemoving
    }

    @MainActor
    private func showSuccess(_ text: String) async {
        successMessage = text
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if successMessage == text {
            successMessage = nil
        }
    }
}
