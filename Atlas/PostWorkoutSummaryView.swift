import SwiftUI
import SwiftData

struct PostWorkoutSummaryView: View {
    let sessionID: UUID
    var onDone: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var weightUnit: String = "lb"

    @State private var session: WorkoutSession?
    @State private var payload: PostWorkoutSummaryPayload?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// VISUAL TWEAK: Tune TL;DR card padding in `tldrCardPadding`.
    private let tldrCardPadding: CGFloat = 14
    /// VISUAL TWEAK: Adjust section spacing in `sectionSpacing`.
    private let sectionSpacing: CGFloat = 16
    /// VISUAL TWEAK: Change max lines shown per exercise row in `exerciseRowMaxLines`.
    private let exerciseRowMaxLines: Int = 1
    /// VISUAL TWEAK: Adjust `summaryCardMaxHeightRatio` to control how tall the summary card can be.
    private let summaryCardMaxHeightRatio: CGFloat = 0.62
    /// VISUAL TWEAK: Change `exerciseGridMaxItems` to show more/less exercises on the one-screen summary.
    private let exerciseGridMaxItems: Int = 6
    /// VISUAL TWEAK: Adjust `minScale` if text feels too tight.
    private let minScale: CGFloat = 0.85

    /// DEV NOTE: This screen caches `aiPostSummaryJSON` so the API is called once per session.
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Summary")
                        .appFont(.title, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(minScale)
                    Text(payload?.sessionDate ?? "Generating summary…")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(minScale)
                }

                if let payload {
                    VStack(alignment: .leading, spacing: sectionSpacing) {
                        tldrCard(payload)
                        summaryCard(payload, maxHeight: geo.size.height * summaryCardMaxHeightRatio)
                    }
                } else if isLoading {
                    ProgressView("Generating summary…")
                        .progressViewStyle(.circular)
                } else if let errorMessage {
                    Text(errorMessage)
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(minScale)
                } else {
                    Text("No summary available.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppStyle.sectionSpacing)

                AtlasPillButton("Done") {
                    dismiss()
                    onDone()
                }
                .padding(.bottom, AppStyle.startButtonBottomPadding)
            }
            .padding(AppStyle.contentPaddingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground))
        }
        .task {
            await load()
        }
    }

    private func tldrCard(_ payload: PostWorkoutSummaryPayload) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(payload.tldr.prefix(5)), id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(.primary).frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(line)
                            .appFont(.body, weight: .regular)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(minScale)
                    }
                }
            }
            .padding(tldrCardPadding)
        }
    }

    private func summaryCard(_ payload: PostWorkoutSummaryPayload, maxHeight: CGFloat) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                totalsRow(payload)
                trainedGrid(payload)
                progressRow(payload)
                nextRow(payload)
                qualityRow(payload)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: maxHeight, alignment: .top)
        }
    }

    private func totalsRow(_ payload: PostWorkoutSummaryPayload) -> some View {
        HStack {
            Text("Totals")
                .appFont(.section, weight: .bold)
            Spacer()
            Text(totalsLine(payload))
                .appFont(.footnote, weight: .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(minScale)
        }
    }

    private func trainedGrid(_ payload: PostWorkoutSummaryPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trained")
                .appFont(.section, weight: .bold)
            let items = Array(payload.sections.trained.prefix(exerciseGridMaxItems))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.exercise)
                            .appFont(.body, weight: .semibold)
                            .lineLimit(exerciseRowMaxLines)
                            .minimumScaleFactor(minScale)
                        Text(item.muscles)
                            .appFont(.footnote, weight: .regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(minScale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if payload.sections.trained.count > exerciseGridMaxItems {
                Text("+\(payload.sections.trained.count - exerciseGridMaxItems) more")
                    .appFont(.footnote, weight: .regular)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressRow(_ payload: PostWorkoutSummaryPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress")
                .appFont(.section, weight: .bold)
            let highlights = Array(payload.sections.progress.prefix(2))
            if highlights.isEmpty {
                Text("No prior history — first log")
                    .appFont(.footnote, weight: .regular)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(highlights, id: \.self) { item in
                    Text("\(item.exercise): \(item.delta)")
                        .appFont(.footnote, weight: .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(minScale)
                }
            }
        }
    }

    private func nextRow(_ payload: PostWorkoutSummaryPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What’s next")
                .appFont(.section, weight: .bold)
            Text(payload.sections.whatsNext.focus)
                .appFont(.body, weight: .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(minScale)
            if let first = payload.sections.whatsNext.targets.first {
                Text(first)
                    .appFont(.footnote, weight: .regular)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(minScale)
            }
        }
    }

    private func qualityRow(_ payload: PostWorkoutSummaryPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quality")
                .appFont(.section, weight: .bold)
            HStack {
                Text("\(payload.sections.quality.rating)/10")
                    .appFont(.title3, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                if let reason = payload.sections.quality.reasons.first {
                    Text(reason)
                        .appFont(.footnote, weight: .regular)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(minScale)
                }
            }
        }
    }

    private func totalsLine(_ payload: PostWorkoutSummaryPayload) -> String {
        // Use TLDR volume if present; otherwise, fallback to summary payload.
        let volumeLine = payload.tldr.first { $0.lowercased().contains("volume:") } ?? ""
        if !volumeLine.isEmpty { return volumeLine }
        return "Volume/sets/reps summarized"
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
        }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let loadedSession = try? modelContext.fetch(descriptor).first
        await MainActor.run {
            self.session = loadedSession
        }
        guard let session = loadedSession else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Session not found."
            }
            return
        }

        if !session.aiPostSummaryJSON.isEmpty {
            if let data = session.aiPostSummaryJSON.data(using: .utf8),
               let payload = try? JSONDecoder().decode(PostWorkoutSummaryPayload.self, from: data) {
                await MainActor.run {
                    self.payload = payload
                    self.isLoading = false
                }
                return
            }
        }

        let previousLogs = try? modelContext.fetch(FetchDescriptor<ExerciseLog>(
            predicate: #Predicate { log in
                log.session?.isCompleted == true && log.session?.id != sessionID
            },
            sortBy: [SortDescriptor(\ExerciseLog.session?.startedAt, order: .reverse)]
        ))
        let previousByExercise: [String: ExerciseLog?] = (previousLogs ?? []).reduce(into: [:]) { dict, log in
            let key = log.name.lowercased()
            if dict[key] == nil {
                dict[key] = log
            }
        }

        let unitPref = WorkoutUnits(from: weightUnit)
        if let result = await RoutineAIService.generatePostWorkoutSummary(session: session, previousSessionsByExercise: previousByExercise, unitPreference: unitPref) {
            await MainActor.run {
                payload = result.payload
                session.aiPostSummaryJSON = result.rawJSON
                session.aiPostSummaryGeneratedAt = Date()
                session.aiPostSummaryModel = result.model
                try? modelContext.save()
                isLoading = false
            }
        } else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Unable to generate summary."
            }
        }
    }
}
