import SwiftUI
import SwiftData

struct PostWorkoutSummaryView: View {
    let sessionID: UUID
    var onDone: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = "lb"

    @StateObject private var loader: PostWorkoutSummaryLoader

    /// VISUAL TWEAK: Change `bodyLineSpacing` to make the text tighter/looser.
    private let bodyLineSpacing: CGFloat = 6
    /// VISUAL TWEAK: Change `titleScale` to make routine name bigger/smaller.
    private let titleScale: CGFloat = 1.0
    /// VISUAL TWEAK: Toggle `showsIndicators` to true if you ever want scroll bar back.
    private let showsIndicators: Bool = false
    /// VISUAL TWEAK: Adjust `minScale` if text feels too tight.
    private let minScale: CGFloat = 0.9

    init(sessionID: UUID, onDone: @escaping () -> Void = {}, loader: PostWorkoutSummaryLoader? = nil) {
        self.sessionID = sessionID
        self.onDone = onDone
        _loader = StateObject(wrappedValue: loader ?? PostWorkoutSummaryLoader())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sessionTitle)
                    .appFont(.title, weight: .semibold)
                    .scaleEffect(titleScale, anchor: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(minScale)
                Text(sessionDateText)
                    .appFont(.body, weight: .regular)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(minScale)
            }

            ScrollView(.vertical, showsIndicators: showsIndicators) {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    localSummaryCard
                    aiSummaryCard
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(AppStyle.contentPaddingLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .atlasBackground()
        .atlasBackgroundTheme(.workout)
        .safeAreaInset(edge: .bottom) {
            AtlasPillButton("Done") {
                dismiss()
                onDone()
            }
            .padding(.horizontal, AppStyle.contentPaddingLarge)
            .padding(.bottom, AppStyle.startButtonBottomPadding)
        }
        .task { await loader.preload(sessionID: sessionID, modelContext: modelContext, unitPreference: WorkoutUnits(from: weightUnit)) }
    }

    // MARK: - Content builders

    private var localSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Summary")
                    .appFont(.section, weight: .bold)
                if loader.localSummaryLines.isEmpty {
                    Text("No sets logged.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(loader.localSummaryLines, id: \.self) { line in
                        Text(line)
                            .appFont(.body, weight: .regular)
                            .lineSpacing(bodyLineSpacing)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.glassContentPadding)
        }
    }

    private var aiSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("AI Summary")
                    .appFont(.section, weight: .bold)
                if loader.payload != nil || (loader.aiSummaryText?.isEmpty == false) {
                    Text(aiContentText())
                        .appFont(.body, weight: .regular)
                        .lineSpacing(bodyLineSpacing)
                        .foregroundStyle(.primary)
                } else if loader.isLoadingAI {
                    VStack(alignment: .leading, spacing: 6) {
                        skeletonLine(width: 0.8)
                        skeletonLine(width: 0.65)
                        skeletonLine(width: 0.5)
                    }
                } else if let errorMessage = loader.errorMessage {
                    Text("Summary unavailable.\n\(errorMessage)")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Summary unavailable.")
                        .appFont(.body, weight: .regular)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.glassContentPadding)
        }
    }

    private func skeletonLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.08))
            .frame(width: UIScreen.main.bounds.width * width, height: 10)
    }

    private var sessionTitle: String {
        loader.session?.routineTitle.isEmpty == false ? loader.session!.routineTitle : "Workout Summary"
    }

    private var sessionDateText: String {
        guard let session = loader.session else { return "Summary" }
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL dd, yyyy (EEEE)"
        return formatter.string(from: session.startedAt)
    }

    private func aiContentText() -> String {
        if let text = loader.aiSummaryText, text.isEmpty == false {
            return text
        }
        if let payload = loader.payload {
            var lines: [String] = []
            if let rating = payload.rating {
                lines.append("Rating: \(String(format: "%.1f", rating))/10")
            }
            if let insight = payload.insight, !insight.isEmpty {
                lines.append("Insight: \(insight)")
            }
            if let prs = payload.prs, !prs.isEmpty {
                lines.append("PRs:")
                lines.append(contentsOf: prs.prefix(2).map { "• \($0)" })
            }
            if let improvements = payload.improvements, !improvements.isEmpty {
                lines.append("Next time:")
                lines.append(contentsOf: improvements.prefix(3).map { "• \($0)" })
            }
            return lines.joined(separator: "\n")
        }
        if let session = loader.session {
            return fallbackImprovements(for: session).joined(separator: "\n")
        }
        return "Summary unavailable."
    }

    private func fallbackImprovements(for session: WorkoutSession) -> [String] {
        let name = session.exercises.first?.name ?? "First lift"
        return [
            "Improvements next time:",
            "• \(name): match last top set and add 1–2 reps if strong.",
            "• Add one accessory if time allows."
        ]
    }
}
