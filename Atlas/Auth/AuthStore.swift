import Foundation
import Combine
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String?
    @Published var email: String?

    private let client: SupabaseClient?
    private let profileService: ProfileService?
    private var didStart = false
    private var isRestoring = false
    private var listenerTask: Task<Void, Never>?
    private var profileEnsureTask: Task<Void, Never>?
    private var lastEnsuredProfileId: UUID?

    init(client: SupabaseClient? = nil) {
        let resolvedClient = client ?? SupabaseClientProvider.makeClient()
        self.client = resolvedClient
        if let resolvedClient {
            profileService = ProfileService(client: resolvedClient)
        } else {
            profileService = nil
        }
        if let current = resolvedClient?.auth.currentSession, current.isExpired == false {
            isAuthenticated = true
            userId = current.user.id.uuidString
            email = current.user.email
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

    func sendMagicLink(email: String, redirectURL: URL?) async throws {
        guard let client else {
            throw AuthError.missingClient
        }
        try await client.auth.signInWithOTP(email: email, redirectTo: redirectURL)
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

        if authenticated == isAuthenticated {
            if authenticated == false {
                if userId != nil || email != nil {
                    userId = nil
                    email = nil
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
            if let session {
                ensureProfile(for: session)
            }
        } else {
            isAuthenticated = false
            userId = nil
            email = nil
            lastEnsuredProfileId = nil
            profileEnsureTask?.cancel()
        }
    }

    private func ensureProfile(for session: Session) {
        guard let profileService else { return }
        let userId = session.user.id
        if lastEnsuredProfileId == userId {
            return
        }

        profileEnsureTask?.cancel()
        profileEnsureTask = Task.detached(priority: .utility) { [weak self] in
            #if DEBUG
            print("[AUTH] ensureProfile start id=\(userId.uuidString) email=\(session.user.email ?? "")")
            #endif
            do {
                try await profileService.ensureProfile(userId: userId, email: session.user.email)
                #if DEBUG
                print("[AUTH] ensureProfile ok")
                #endif
                await MainActor.run { [weak self] in
                    self?.lastEnsuredProfileId = userId
                }
            } catch {
                #if DEBUG
                print("[AUTH][ERROR] ensureProfile failed: \(error)")
                #endif
                await MainActor.run { [weak self] in
                    if self?.lastEnsuredProfileId == userId {
                        self?.lastEnsuredProfileId = nil
                    }
                }
            }
        }
    }
}

enum AuthError: Error {
    case missingClient
}
