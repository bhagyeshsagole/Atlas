import SwiftUI
import SwiftData

struct SessionHistoryDetailSheetView: View {
    let session: WorkoutSession
    let onRemove: () -> Void
    let preferredUnit: WorkoutUnits

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false

    var body: some View {
        let vm = SessionDetailVM(session: session, preferredUnit: preferredUnit)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SessionHeaderCard(title: vm.headerTitle, dateText: vm.headerDateString)
                    SummaryRow(sets: vm.summarySetsText, reps: vm.summaryRepsText, volume: vm.summaryVolumeText)
                    ExerciseSectionList(sections: vm.exerciseSections)
                    removeButton
                }
                .padding(AppStyle.contentPaddingLarge)
            }
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showConfirm) {
                GlassConfirmPopup(
                    title: "Remove this session?",
                    message: "This cannot be undone.",
                    primaryTitle: "Remove",
                    secondaryTitle: "Cancel",
                    isDestructive: true,
                    isPresented: $showConfirm,
                    onPrimary: {
                        Haptics.playMediumImpact()
                        onRemove()
                    },
                    onSecondary: {}
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var removeButton: some View {
        Button {
            showConfirm = true
        } label: {
            Text("Remove Session")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1)
                )
        }
        .padding(.top, 8)
    }
}

// MARK: - View Model

private struct SessionDetailVM {
    struct SetRow: Identifiable {
        let id: UUID
        let title: String
        let weightText: String
        let repsText: String
        let tag: SetTag?
    }

    struct ExerciseSection: Identifiable {
        let id: UUID
        let name: String
        let sets: [SetRow]
    }

    let headerTitle: String
    let headerDateString: String
    let summarySetsText: String
    let summaryRepsText: String
    let summaryVolumeText: String
    let exerciseSections: [ExerciseSection]

    init(session: WorkoutSession, preferredUnit: WorkoutUnits) {
        headerTitle = session.routineTitle.isEmpty ? "Session" : session.routineTitle
        headerDateString = SessionDetailVM.dateString(session.endedAt ?? session.startedAt)
        summarySetsText = "\(session.totalSets)"
        summaryRepsText = "\(session.totalReps)"
        summaryVolumeText = WorkoutSessionFormatter.volumeString(volumeKg: session.volumeKg, unit: preferredUnit)

        let exercises = session.exercises
            .filter { $0.hasLoggedWork }
            .sorted(by: { $0.orderIndex < $1.orderIndex })
        exerciseSections = exercises.map { exercise in
            let sets = exercise.sets.sorted(by: { $0.createdAt < $1.createdAt })
            let rows: [SetRow] = sets.enumerated().map { idx, set in
                return SetRow(
                    id: set.id,
                    title: "Set \(idx + 1)",
                    weightText: WeightFormatter.format(set.weightKg ?? 0, unit: preferredUnit),
                    repsText: "× \(set.reps)",
                    tag: SetTag(rawValue: set.tag)
                )
            }
            return ExerciseSection(id: exercise.id, name: exercise.name, sets: rows)
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // tagDisplay helper not needed externally anymore; tag display lives on SetTag extension below.
}

// MARK: - Subviews

private struct SessionHeaderCard: View {
    let title: String
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.title3, weight: .bold)
            Text(dateText)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ExerciseLog {
    var hasLoggedWork: Bool {
        !sets.isEmpty && sets.contains { $0.reps > 0 }
    }
}

private struct SummaryRow: View {
    let sets: String
    let reps: String
    let volume: String

    var body: some View {
        GlassCard {
            HStack {
                summaryItem(title: "Sets", value: sets)
                Spacer()
                summaryItem(title: "Reps", value: reps)
                Spacer()
                summaryItem(title: "Volume", value: volume)
            }
            .padding(AppStyle.glassContentPadding)
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.body, weight: .semibold)
        }
    }
}

private struct ExerciseSectionList: View {
    let sections: [SessionDetailVM.ExerciseSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercises")
                .appFont(.section, weight: .bold)
            VStack(spacing: 10) {
                ForEach(sections) { section in
                    ExerciseSectionCard(section: section)
                }
            }
        }
    }
}

private struct ExerciseSectionCard: View {
    let section: SessionDetailVM.ExerciseSection

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(section.name)
                    .appFont(.body, weight: .semibold)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.sets) { row in
                        SetRowView(row: row)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppStyle.glassContentPadding)
        }
    }
}

private struct SetRowView: View {
    let row: SessionDetailVM.SetRow

    var body: some View {
        HStack {
            Text(row.title)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            Text(row.weightText)
                .appFont(.body, weight: .semibold)
            Text(row.repsText)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
            if let tag = row.tag {
                Text(tag.displayName)
                    .appFont(.caption, weight: .bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            Spacer()
        }
    }
}
