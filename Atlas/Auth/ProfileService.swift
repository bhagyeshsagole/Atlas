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
        let height_cm: Double?
        let weight_kg: Double?
        let workouts_per_week: Int?
        let training_goal: String?
        let experience_level: String?
        let limitations: String?
        let onboarding_completed: Bool?
    }

    private struct SetUsernameRow: Encodable {
        let username: String
    }

    private struct TrainingProfileUpsertRow: Encodable {
        let height_cm: Double?
        let weight_kg: Double?
        let workouts_per_week: Int?
        let training_goal: String?
        let experience_level: String?
        let limitations: String?
        let onboarding_completed: Bool
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

    func fetchMyProfile(userId: UUID) async throws -> (id: UUID, email: String?, username: String?, training: TrainingProfile) {
        let response: [ProfileRow] = try await client
            .from("profiles")
            .select("id,email,username,height_cm,weight_kg,workouts_per_week,training_goal,experience_level,limitations,onboarding_completed")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        guard let row = response.first else {
            throw ProfileServiceError.notFound
        }
        let training = TrainingProfile(
            heightCm: row.height_cm,
            weightKg: row.weight_kg,
            workoutsPerWeek: row.workouts_per_week,
            goal: row.training_goal,
            experienceLevel: row.experience_level,
            limitations: row.limitations,
            onboardingCompleted: row.onboarding_completed ?? false
        )
        return (row.id, row.email, row.username, training)
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

    func setTrainingProfile(userId: UUID, profile: TrainingProfile) async throws {
        let payload = TrainingProfileUpsertRow(
            height_cm: profile.heightCm,
            weight_kg: profile.weightKg,
            workouts_per_week: profile.workoutsPerWeek,
            training_goal: profile.goal,
            experience_level: profile.experienceLevel,
            limitations: profile.limitations,
            onboarding_completed: profile.onboardingCompleted
        )
        _ = try await client
            .from("profiles")
            .update(payload, returning: .minimal)
            .eq("id", value: userId)
            .execute()
    }
}

enum ProfileServiceError: Error {
    case notFound
    case duplicateUsername
    case invalidUsername
}
