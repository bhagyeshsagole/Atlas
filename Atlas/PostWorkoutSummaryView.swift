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
                Text(contentText())
                    .appFont(.body, weight: .regular)
                    .lineSpacing(bodyLineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
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
        .task { await loader.preload(sessionID: sessionID, modelContext: modelContext) }
    }

    // MARK: - Content builders

    private func contentText() -> String {
        if let cached = loader.session?.aiPostSummaryText, cached.isEmpty == false {
            return cached
        }
        if let payload = loader.payload, let session = loader.session {
            return buildDisplayText(with: payload, for: session)
        }
        if loader.isLoading {
            return "Generating summary…"
        }
        if let errorMessage = loader.errorMessage {
            return "Summary unavailable.\n\(errorMessage)"
        }
        return "Summary unavailable."
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

    private func computeTotals(session: WorkoutSession) -> (volumeKg: Double, sets: Int, reps: Int) {
        var volume: Double = 0
        var setsCount = 0
        var repsCount = 0
        for exercise in session.exercises {
            for set in exercise.sets {
                setsCount += 1
                repsCount += set.reps
                if let w = set.weightKg {
                    volume += w * Double(set.reps)
                }
            }
        }
        return (volume, setsCount, repsCount)
    }

    private func buildDisplayText(with payload: PostWorkoutSummaryPayload?, for session: WorkoutSession) -> String {
        let totals = computeTotals(session: session)
        let unitPref = WorkoutUnits(from: weightUnit)
        let volumeValue = unitPref == .kg ? totals.volumeKg : totals.volumeKg * WorkoutSessionFormatter.kgToLb
        let volumeText = String(format: "%.0f %@", volumeValue, unitPref == .kg ? "kg" : "lb")
        let setsRepsLine = "Sets / Reps: \(totals.sets) sets / \(totals.reps) reps"

        let ratingValue = payload?.rating.map { String(format: "%.1f", $0) } ?? "—"
        let insight = (payload?.insight?.isEmpty == false ? payload?.insight : nil) ?? "Summary unavailable."
        let ratingLine = "\(ratingValue)/10 — \(insight)"

        let prs = Array((payload?.prs ?? []).prefix(2)).filter { !$0.isEmpty }
        let prLines: [String]
        if prs.isEmpty {
            prLines = ["PRs: None"]
        } else {
            prLines = ["PRs:"] + prs.map { "• \($0)" }
        }

        let improvementsRaw = Array((payload?.improvements ?? []).prefix(3)).filter { !$0.isEmpty }
        let improvements: [String]
        if improvementsRaw.isEmpty {
            improvements = fallbackImprovements(for: session)
        } else {
            improvements = ["Improvements next time:"] + improvementsRaw.map { "• \($0)" }
        }

        var lines: [String] = []
        lines.append("Training volume: \(volumeText)")
        lines.append(setsRepsLine)
        lines.append(ratingLine)
        lines.append(contentsOf: prLines)
        lines.append(contentsOf: improvements)
        return lines.joined(separator: "\n")
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
