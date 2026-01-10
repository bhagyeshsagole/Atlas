import SwiftUI

struct StatsView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    Text("Stats")
                        .appFont(.title, weight: .semibold)
                        .foregroundStyle(.white)

                    GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coming soon")
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(.white)
                            Text("Your session metrics will land here.")
                                .appFont(.footnote)
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, AppStyle.screenHorizontalPadding)
                .padding(.top, AppStyle.screenTopPadding + AppStyle.headerTopPadding)
                .padding(.bottom, AppStyle.settingsBottomPadding)
            }
        }
        .tint(.primary)
    }
}
