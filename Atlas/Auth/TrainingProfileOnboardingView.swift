import SwiftUI

struct TrainingProfileOnboardingView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var heightCm: Double?
    @State private var weightKg: Double?
    @State private var workoutsPerWeek: Int = 3
    @State private var goal: String = ""
    @State private var experience: String = ""
    @State private var limitations: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    var onComplete: () -> Void

    private let goals = ["Strength", "Hypertrophy", "Fat loss", "General fitness"]
    private let experiences = ["Beginner", "Intermediate", "Advanced"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set up your training profile")
                            .appFont(.title, weight: .bold)
                        Text("We use this to tailor guidance. You can edit later in Settings.")
                            .appFont(.body)
                            .foregroundStyle(.secondary)
                    }

                    GlassCardSection {
                        VStack(alignment: .leading, spacing: 12) {
                            NumberField(title: "Height (cm)", value: Binding(
                                get: { heightCm.map { String(Int($0)) } ?? "" },
                                set: { heightCm = Double($0) }
                            ))
                            NumberField(title: "Weight (kg)", value: Binding(
                                get: { weightKg.map { String(Int($0)) } ?? "" },
                                set: { weightKg = Double($0) }
                            ))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Workouts per week")
                                    .appFont(.section, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    ForEach(1...7, id: \.self) { num in
                                        Button {
                                            workoutsPerWeek = num
                                            Haptics.playLightTap()
                                        } label: {
                                            Text("\(num)")
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(num == workoutsPerWeek ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GlassCardSection {
                        VStack(alignment: .leading, spacing: 12) {
                            ChipPicker(title: "Primary goal", options: goals, selection: $goal)
                            ChipPicker(title: "Experience level", options: experiences, selection: $experience)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Limitations / injuries (optional)")
                                    .appFont(.section, weight: .semibold)
                                    .foregroundStyle(.secondary)
                                TextField("None", text: $limitations, axis: .vertical)
                                    .padding(AppStyle.settingsGroupPadding)
                                    .atlasGlassCard()
                                    .lineLimit(3)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .appFont(.body)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView().tint(.primary) }
                            Text("Finish")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .atlasGlassCard()
                    }
                    .disabled(isWorking || isValid == false)
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding)
                .padding(.bottom, 32)
            }
            .background(Color.black.opacity(0.94).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Training Profile")
                        .appFont(.title3, weight: .bold)
                }
            }
        }
        .atlasBackground()
        .atlasBackgroundTheme(.auth)
    }

    private var isValid: Bool {
        heightCm != nil && weightKg != nil && goal.isEmpty == false && experience.isEmpty == false
    }

    @MainActor
    private func saveProfile() async {
        guard isValid else { return }
        isWorking = true
        errorMessage = nil
        let profile = TrainingProfile(
            heightCm: heightCm,
            weightKg: weightKg,
            workoutsPerWeek: workoutsPerWeek,
            goal: goal,
            experienceLevel: experience,
            limitations: limitations.isEmpty ? nil : limitations,
            onboardingCompleted: true
        )
        let result = await authStore.updateTrainingProfile(profile)
        if let result { errorMessage = result }
        onComplete()
        isWorking = false
    }
}

private struct GlassCardSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(AppStyle.settingsGroupPadding)
        .atlasGlassCard()
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.section, weight: .semibold)
                .foregroundStyle(.secondary)
            TextField("0", text: $value)
                .keyboardType(.numberPad)
                .padding(AppStyle.settingsGroupPadding)
                .atlasGlassCard()
        }
    }
}

private struct ChipPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.section, weight: .semibold)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                        Haptics.playLightTap()
                    } label: {
                        Text(option)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selection == option ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
