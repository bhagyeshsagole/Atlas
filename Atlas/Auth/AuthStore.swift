import Foundation
import Combine
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userId: String? = nil
    @Published var email: String? = nil

    private let client: SupabaseClient?
    private var hasBootstrapped = false
    private var hasStartedListener = false

    init(client: SupabaseClient? = nil) {
        let resolvedClient = client ?? SupabaseClientProvider.makeClient()
        self.client = resolvedClient
        if let current = resolvedClient?.auth.currentSession, current.isExpired == false {
            isAuthenticated = true
            userId = current.user.id.uuidString
            email = current.user.email
        }
        #if DEBUG
        print("[AUTH] boot session present=\(isAuthenticated)")
        #endif
    }

    func sendMagicLink(email: String, redirectURL: URL?) async throws {
        guard let client else {
            throw AuthError.missingClient
        }
        try await client.auth.signInWithOTP(email: email, redirectTo: redirectURL)
    }

    func restoreSessionIfNeeded() async {
        guard hasBootstrapped == false else { return }
        hasBootstrapped = true

        guard let client else {
            #if DEBUG
            print("[AUTH] restore skipped (Supabase client unavailable)")
            #endif
            await updateState(with: nil)
            return
        }

        let session = client.auth.currentSession
        await handleSessionUpdate(session)
        #if DEBUG
        print("[AUTH] restored authenticated=\(isAuthenticated)")
        #endif
    }

    func handleAuthRedirect(_ url: URL) {
        guard let client else {
            #if DEBUG
            print("[AUTH] handle redirect skipped (client unavailable)")
            #endif
            return
        }
        client.handle(url)
        Task { await restoreSessionIfNeeded() }
    }

    func signOut() async {
        do {
            try await client?.auth.signOut()
        } catch {
            #if DEBUG
            print("[AUTH][WARN] signOut failed: \(error)")
            #endif
        }
        await updateState(with: nil)
    }

    func startAuthListener() {
        guard hasStartedListener == false else { return }
        hasStartedListener = true
        guard let client else {
            #if DEBUG
            print("[AUTH] listener skipped (Supabase client unavailable)")
            #endif
            return
        }

        Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                await self.handleSessionUpdate(session)
                #if DEBUG
                print("[AUTH] state changed event=\(event) authenticated=\(self.isAuthenticated)")
                #endif
            }
        }
    }

    private func handleSessionUpdate(_ session: Session?) async {
        if let session, session.isExpired {
            do {
                try await client?.auth.signOut()
            } catch {
                #if DEBUG
                print("[AUTH][WARN] signOut failed for expired session: \(error)")
                #endif
            }
            await updateState(with: nil)
            return
        }
        await updateState(with: session)
    }

    private func updateState(with session: Session?) async {
        await MainActor.run {
            if let session, session.isExpired == false {
                isAuthenticated = true
                userId = session.user.id.uuidString
                email = session.user.email
            } else {
                isAuthenticated = false
                userId = nil
                email = nil
            }
        }
    }
}

enum AuthError: Error {
    case missingClient
}
