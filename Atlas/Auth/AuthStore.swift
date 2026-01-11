import Foundation
import Combine
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String?
    @Published var email: String?
    @Published var username: String?
    @Published var trainingProfile: TrainingProfile = .empty
    @Published var isProfileLoaded: Bool = false
    @Published private(set) var session: Session?
    @Published var authErrorMessage: String?
    @Published var isGuestMode: Bool = false

    private let client: SupabaseClient?
    private let profileService: ProfileService?
    private let trainingProfileStore = TrainingProfileStore()
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

    var needsOnboarding: Bool {
        isAuthenticated && (trainingProfile.onboardingCompleted == false)
    }

    init(client: SupabaseClient? = nil) {
        let resolvedClient = client ?? SupabaseService.shared
        self.client = resolvedClient
        if let resolvedClient {
            profileService = ProfileService(client: resolvedClient)
        } else {
            profileService = nil
        }
        #if DEBUG
        print("[AUTH] supabase configured=\(resolvedClient != nil)")
        #endif
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if let resolvedClient {
                await self.loadInitialSession(client: resolvedClient)
            }
        }
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
        if isGuestMode == false {
            kickoffRestore()
            kickoffListener()
        }
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
            if let username = rawUsername, username.isEmpty == false {
                _ = await setUsername(username)
            }
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
        isGuestMode = false
        apply(session: nil, event: nil)
    }

    func activateDemoMode() {
        isGuestMode = true
        isAuthenticated = true
        isProfileLoaded = true
        authErrorMessage = nil
        session = nil
        userId = nil
        email = "guest@atlas.app"
        username = "Guest"
        trainingProfile = TrainingProfile(heightCm: nil, weightKg: nil, workoutsPerWeek: nil, goal: nil, experienceLevel: nil, limitations: nil, onboardingCompleted: true)
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
            await self?.loadInitialSession(client: client)
            await MainActor.run { [weak self] in
                self?.isRestoring = false
            }
        }
    }

    private func loadInitialSession(client: SupabaseClient) async {
        do {
            let session = try await client.auth.session
            let expired = session.isExpired
            let authenticated = expired == false
            await MainActor.run { [weak self] in
                self?.apply(session: authenticated ? session : nil, event: nil)
            }
            #if DEBUG
            let uid = session.user.id.uuidString
            print("[AUTH] initial session loaded authenticated=\(authenticated) user=\(uid)")
            #endif
        } catch {
            let session = client.auth.currentSession
            let expired = session?.isExpired ?? false
            let authenticated = session != nil && expired == false
            await MainActor.run { [weak self] in
                self?.apply(session: authenticated ? session : nil, event: nil)
            }
            #if DEBUG
            print("[AUTH] initial session fallback authenticated=\(authenticated)")
            #endif
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
        if isGuestMode {
            // Keep guest session stable without Supabase.
            isAuthenticated = true
            isProfileLoaded = true
            return
        }
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
                trainingProfile = profile.training
                if let userId = self.currentUserId {
                    trainingProfileStore.save(profile.training, for: userId)
                }
            }
            #if DEBUG
            print("[PROFILE] refresh ok username=\(profile.username ?? "nil")")
            #endif
        } catch {
            #if DEBUG
            print("[PROFILE][WARN] refresh failed: \(error)")
            #endif
            if let cached = currentUserId.flatMap({ trainingProfileStore.load(for: $0) }) {
                trainingProfile = cached
            }
        }
        isProfileLoaded = true
    }

    func updateTrainingProfile(_ profile: TrainingProfile) async -> String? {
        guard let userId = currentUserId else { return "Not signed in." }
        trainingProfile = profile
        trainingProfileStore.save(profile, for: userId)
        guard let profileService else { return nil }
        do {
            try await profileService.setTrainingProfile(userId: userId, profile: profile)
            return nil
        } catch {
            #if DEBUG
            print("[PROFILE][ERROR] training profile save failed: \(error)")
            #endif
            return "Could not save online; saved locally and will retry later."
        }
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
