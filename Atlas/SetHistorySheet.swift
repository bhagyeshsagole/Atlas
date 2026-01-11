import SwiftUI

struct SetHistorySheet: View {
    let sets: [SetLog]
    let weightText: (SetLog) -> String
    let onDelete: (SetLog) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sets) { set in
                        HStack(spacing: 12) {
                            if let tag = SetTag(rawValue: set.tag) {
                                Text(tag.displayName)
                                    .appFont(.caption, weight: .bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(.white.opacity(0.08)))
                            }
                            Text("\(weightText(set)) × \(set.reps)")
                                .appFont(.body, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Spacer()
                            Button(role: .destructive) {
                                onDelete(set)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                                    .labelStyle(.titleAndIcon)
                                    .appFont(.footnote, weight: .semibold)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(AppStyle.glassContentPadding)
                        .atlasGlassCard()
                    }
                }
                .padding(.horizontal, AppStyle.contentPaddingLarge)
                .padding(.top, AppStyle.contentPaddingLarge)
                .padding(.bottom, AppStyle.contentPaddingLarge)
            }
            .scrollIndicators(.hidden)
            .atlasBackground()
            .atlasBackgroundTheme(.workout)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("All Sets")
                        .appFont(.headline, weight: .semibold)
                }
            }
        }
    }
}
