import Foundation
import Supabase

struct ProfileService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    private struct ProfileUpsertRow: Encodable {
        let id: UUID
        let email: String?
    }

    private struct ProfileRow: Decodable {
        let id: UUID
        let email: String?
        let username: String?
    }

    private struct SetUsernameRow: Encodable {
        let username: String
    }

    func ensureProfile(userId: UUID, email: String?) async throws {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ProfileUpsertRow(
            id: userId,
            email: (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
        )

        // Upsert by primary key (id). Safe to call multiple times.
        _ = try await client
            .from("profiles")
            .upsert(payload, onConflict: "id", returning: .minimal)
            .execute()
    }

    func fetchMyProfile(userId: UUID) async throws -> (id: UUID, email: String?, username: String?) {
        let response: [ProfileRow] = try await client
            .from("profiles")
            .select("id,email,username")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        guard let row = response.first else {
            throw ProfileServiceError.notFound
        }
        return (row.id, row.email, row.username)
    }

    func setUsername(userId: UUID, username: String) async throws {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let payload = SetUsernameRow(username: normalized)
        do {
            _ = try await client
                .from("profiles")
                .update(payload, returning: .minimal)
                .eq("id", value: userId)
                .execute()
        } catch {
            if error.localizedDescription.lowercased().contains("duplicate") ||
                error.localizedDescription.lowercased().contains("unique") {
                throw ProfileServiceError.duplicateUsername
            }
            if error.localizedDescription.lowercased().contains("check constraint") {
                throw ProfileServiceError.invalidUsername
            }
            throw error
        }
    }
}

enum ProfileServiceError: Error {
    case notFound
    case duplicateUsername
    case invalidUsername
}
