import Foundation
import Combine
import SwiftData

@MainActor
final class PostWorkoutSummaryLoader: ObservableObject {
    @Published var session: WorkoutSession?
    @Published var payload: PostWorkoutSummaryPayload?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func preload(sessionID: UUID, modelContext: ModelContext) async {
        if session?.id == sessionID, isLoading == false { return }
        await load(sessionID: sessionID, modelContext: modelContext)
    }

    func load(sessionID: UUID, modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil

        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let loadedSession = (try? modelContext.fetch(descriptor))?.first(where: { $0.id == sessionID })
        session = loadedSession

        guard let session else {
            errorMessage = "Session not found."
            isLoading = false
            return
        }

        if session.aiPostSummaryJSON.isEmpty == false {
            payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: Data(session.aiPostSummaryJSON.utf8))
            isLoading = false
            return
        }

        // If we have cached text only, render it immediately.
        if session.aiPostSummaryText.isEmpty == false {
            isLoading = false
            return
        }

        // No cached summary; leave loading state for the view to trigger generation if needed.
        isLoading = false
    }
}
