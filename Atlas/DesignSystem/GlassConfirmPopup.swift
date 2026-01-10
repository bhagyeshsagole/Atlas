import SwiftUI

struct GlassConfirmPopup: View {
    let title: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String
    let isDestructive: Bool
    @Binding var isPresented: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            isPresented = false
                        }
                        onSecondary()
                    }

                GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .appFont(.title3, weight: .semibold)
                            .foregroundStyle(.primary)
                        Text(message)
                            .appFont(.body, weight: .regular)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            AtlasPillButton(secondaryTitle) {
                                Haptics.playLightTap()
                                withAnimation(.easeInOut) {
                                    isPresented = false
                                }
                                onSecondary()
                            }
                            .frame(maxWidth: .infinity)

                            AtlasPillButton(primaryTitle) {
                                if isDestructive {
                                    Haptics.playMediumTap()
                                } else {
                                    Haptics.playLightTap()
                                }
                                withAnimation(.easeInOut) {
                                    isPresented = false
                                }
                                onPrimary()
                            }
                            .frame(maxWidth: .infinity)
                            .tint(isDestructive ? .red : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 30)
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    Haptics.playLightTap()
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isPresented)
            .zIndex(5)
        }
    }
}
