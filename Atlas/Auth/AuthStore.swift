import Foundation
import Combine
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String?
    @Published var email: String?
    @Published var username: String?
    @Published var isProfileLoaded: Bool = false
    @Published private(set) var session: Session?
    @Published var authErrorMessage: String?

    private let client: SupabaseClient?
    private let profileService: ProfileService?
    private var didStart = false
    private var isRestoring = false
    private var listenerTask: Task<Void, Never>?
    private var profileEnsureTask: Task<Void, Never>?
    private var lastEnsuredProfileId: UUID?

    var supabaseClient: SupabaseClient? { client }
    var currentUserId: UUID? {
        if let id = session?.user.id {
            return id
        }
        if let idString = userId, let id = UUID(uuidString: idString) {
            return id
        }
        return nil
    }
    var isReadyForFriends: Bool {
        client != nil && isAuthenticated && (session?.isExpired == false) && currentUserId != nil
    }
    var isProfileComplete: Bool {
        isAuthenticated && (username?.isEmpty == false)
    }

    init(client: SupabaseClient? = nil) {
        let resolvedClient = client ?? SupabaseClientProvider.makeClient()
        self.client = resolvedClient
        if let resolvedClient {
            profileService = ProfileService(client: resolvedClient)
        } else {
            profileService = nil
        }
        #if DEBUG
        print("[AUTH] supabase configured=\(resolvedClient != nil)")
        #endif
        if let current = resolvedClient?.auth.currentSession, current.isExpired == false {
            isAuthenticated = true
            session = current
            userId = current.user.id.uuidString
            email = current.user.email
            isProfileLoaded = false
            Task { await refreshProfile() }
        }
        #if DEBUG
        print("[AUTH] boot session present=\(isAuthenticated)")
        #endif
    }

    deinit {
        listenerTask?.cancel()
        profileEnsureTask?.cancel()
    }

    func startIfNeeded() {
        guard didStart == false else { return }
        didStart = true
        #if DEBUG
        print("[AUTH] startIfNeeded")
        #endif
        kickoffRestore()
        kickoffListener()
    }

    func signIn(email rawEmail: String, password rawPassword: String) async -> String? {
        guard let client else { return "Supabase not configured." }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.isEmpty == false else { return "Enter an email." }
        guard password.isEmpty == false else { return "Enter a password." }

        do {
            #if DEBUG
            print("[AUTH][UI] signIn begin email=\(email)")
            #endif
            _ = try await client.auth.signIn(email: email, password: password)
            authErrorMessage = nil
            apply(session: client.auth.currentSession, event: nil)
            await refreshProfile()
            #if DEBUG
            let uid = client.auth.currentSession?.user.id.uuidString ?? "nil"
            print("[AUTH][UI] signIn ok user=\(uid)")
            #endif
            return nil
        } catch {
            let friendly = friendlyAuthMessage(for: error)
            authErrorMessage = friendly
            #if DEBUG
            print("[AUTH][UI] signIn failed: \(friendly)")
            #endif
            return authErrorMessage
        }
    }

    func signUp(email rawEmail: String, password rawPassword: String, username rawUsername: String?) async -> String? {
        guard let client else { return "Supabase not configured." }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.isEmpty == false else { return "Enter an email." }
        guard password.count >= 6 else { return "Password must be at least 6 characters." }

        do {
            _ = try await client.auth.signUp(email: email, password: password)
            authErrorMessage = nil
            apply(session: client.auth.currentSession, event: nil)
            await refreshProfile()
            return nil
        } catch {
            authErrorMessage = friendlyAuthMessage(for: error)
            #if DEBUG
            print("[AUTH][ERROR] signUp failed: \(error)")
            #endif
            return authErrorMessage
        }
    }

    func handleAuthRedirect(_ url: URL) {
        #if DEBUG
        print("[AUTH] handled deep link url=\(url.absoluteString)")
        #endif
        guard let client else {
            #if DEBUG
            print("[AUTH] handle redirect skipped (client unavailable)")
            #endif
            return
        }
        client.handle(url)
    }

    func restoreSessionIfNeeded() async {
        if didStart == false {
            startIfNeeded()
            return
        }
        kickoffRestore()
    }

    func signOut() async {
        do {
            try await client?.auth.signOut()
        } catch {
            #if DEBUG
            print("[AUTH][WARN] signOut failed: \(error)")
            #endif
        }
        apply(session: nil, event: nil)
    }

    private func kickoffRestore() {
        guard isRestoring == false else { return }
        isRestoring = true
        #if DEBUG
        print("[AUTH] restore begin")
        #endif
        guard let client else {
            #if DEBUG
            print("[AUTH] restore end authenticated=false (client unavailable)")
            #endif
            isRestoring = false
            apply(session: nil, event: nil)
            return
        }

        Task.detached(priority: .utility) { [weak self, client] in
            let session = client.auth.currentSession
            let expired = session?.isExpired ?? false
            let authenticated = session != nil && expired == false
            await MainActor.run { [weak self] in
                guard let self else { return }
                defer { self.isRestoring = false }
                self.apply(session: session, event: nil)
                #if DEBUG
                print("[AUTH] restore end authenticated=\(authenticated)")
                #endif
            }
        }
    }

    private func kickoffListener() {
        guard listenerTask == nil else { return }
        guard let client else {
            #if DEBUG
            print("[AUTH] listener skipped (Supabase client unavailable)")
            #endif
            return
        }

        listenerTask = Task.detached(priority: .utility) { [weak self, client] in
            #if DEBUG
            print("[AUTH] listener started")
            #endif
            for await (event, session) in client.auth.authStateChanges {
                let expired = session?.isExpired ?? false
                let authenticated = session != nil && expired == false
                #if DEBUG
                print("[AUTH] event=\(event) authenticated=\(authenticated) expired=\(expired)")
                #endif
                await MainActor.run { [weak self] in
                    self?.apply(session: session, event: event)
                }
            }
        }
    }

    private func apply(session: Session?, event: AuthChangeEvent?) {
        _ = event
        let expired = session?.isExpired ?? false
        let authenticated = session != nil && expired == false
        let newUserId = session?.user.id.uuidString
        let newEmail = session?.user.email
        self.session = authenticated ? session : nil

        if authenticated == isAuthenticated {
            if authenticated == false {
                if userId != nil || email != nil {
                    userId = nil
                    email = nil
                    username = nil
                    isProfileLoaded = false
                    lastEnsuredProfileId = nil
                    profileEnsureTask?.cancel()
                }
                return
            }
            if newUserId == userId && newEmail == email {
                return
            }
        }

        if authenticated, let newUserId, let newEmail {
            isAuthenticated = true
            userId = newUserId
            email = newEmail
            authErrorMessage = nil
            isProfileLoaded = false
            if let session {
                ensureProfile(for: session)
                Task { await refreshProfile() }
            }
        } else {
            isAuthenticated = false
            userId = nil
            email = nil
            username = nil
            isProfileLoaded = false
            authErrorMessage = nil
            lastEnsuredProfileId = nil
            profileEnsureTask?.cancel()
        }
        #if DEBUG
        let readyUser = currentUserId?.uuidString ?? "nil"
        let expiredFlag = self.session?.isExpired ?? true
        print("[AUTH] ready client=\(client != nil) authed=\(isAuthenticated) userId=\(readyUser) expired=\(expiredFlag)")
        #endif
    }

    private func ensureProfile(for session: Session) {
        guard let profileService else { return }
        let userId = session.user.id
        if lastEnsuredProfileId == userId {
            return
        }

        profileEnsureTask?.cancel()
        profileEnsureTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await profileService.ensureProfile(userId: userId, email: session.user.email)
                #if DEBUG
                print("[PROFILE] ensured id=\(userId.uuidString)")
                #endif
                await MainActor.run { [weak self] in
                    self?.lastEnsuredProfileId = userId
                }
            } catch {
                #if DEBUG
                print("[PROFILE][ERROR] ensure failed: \(error)")
                #endif
                await MainActor.run { [weak self] in
                    if self?.lastEnsuredProfileId == userId {
                        self?.lastEnsuredProfileId = nil
                    }
                }
            }
        }
    }

    private func friendlyAuthMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("invalid login") || message.contains("invalid email or password") {
            return "Email not found, try creating account."
        }
        if message.contains("email not confirmed") {
            return "Email not found, try creating account."
        }
        if message.contains("password") {
            return "Check your password and try again."
        }
        if message.contains("network") || message.contains("timeout") {
            return "Network error. Try again."
        }
        if message.contains("supabase") && message.contains("config") {
            return "Supabase config missing."
        }
        return "Authentication failed. Try again."
    }

    func refreshProfile() async {
        guard let profileService, let userId = currentUserId else {
            isProfileLoaded = true
            return
        }
        #if DEBUG
        print("[PROFILE] refresh begin")
        #endif
        isProfileLoaded = false
        do {
            let profile = try await profileService.fetchMyProfile(userId: userId)
            await MainActor.run {
                username = profile.username
            }
            #if DEBUG
            print("[PROFILE] refresh ok username=\(profile.username ?? "nil")")
            #endif
        } catch {
            #if DEBUG
            print("[PROFILE][WARN] refresh failed: \(error)")
            #endif
        }
        isProfileLoaded = true
    }

    func setUsername(_ newUsername: String) async -> String? {
        guard let profileService, let userId = currentUserId else {
            return "Not signed in."
        }
        do {
            try await profileService.setUsername(userId: userId, username: newUsername)
            await MainActor.run {
                self.username = newUsername
            }
            #if DEBUG
            print("[PROFILE] setUsername success")
            #endif
            await refreshProfile()
            return nil
        } catch {
            #if DEBUG
            print("[PROFILE][ERROR] setUsername failed: \(error.localizedDescription)")
            #endif
            if let err = error as? ProfileServiceError {
                switch err {
                case .duplicateUsername:
                    return "Username is taken."
                case .invalidUsername:
                    return "Usernames are 3–20 chars: a–z, 0–9, underscore."
                case .notFound:
                    return "Profile not found."
                }
            } else if isUniqueViolation(error) {
                return "Username is taken."
            }
            return "Couldn't save username. Try again."
        }
    }
}

private func isUniqueViolation(_ error: Error) -> Bool {
    if let pg = error as? PostgrestError {
        if pg.code == "23505" { return true }
        let msg = (pg.message ?? "").lowercased()
        if msg.contains("duplicate key") || msg.contains("unique") { return true }
    }
    return false
}

enum AuthError: Error {
    case missingClient
}
