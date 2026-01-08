import Foundation
import Supabase

struct ProfileService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // Strongly-typed payload for the `profiles` table.
    private struct ProfileUpsertRow: Encodable {
        let id: UUID
        let email: String?
    }

    func ensureProfile(userId: UUID, email: String?) async throws {
        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = ProfileUpsertRow(
            id: userId,
            email: (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
        )

        // Upsert by primary key (id). Safe to call multiple times.
        _ = try await client.database
            .from("profiles")
            .upsert(row, onConflict: "id", returning: .minimal)
            .execute()
    }
}
