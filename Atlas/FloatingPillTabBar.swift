import SwiftUI

struct FloatingPillTabBar: View {
    @Binding var selectedTab: AppTab
    private let tabHeight: CGFloat = 76
    private let pressedScale: CGFloat = 0.96

    var body: some View {
        HStack(spacing: 0) {
            tabItem(for: .home, systemName: "house.fill", title: "Home")
            tabItem(for: .friends, systemName: "person.2.fill", title: "Friends")
            tabItem(for: .stats, systemName: "chart.bar.fill", title: "Stats")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: tabHeight)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 10)
        .clipShape(Capsule())
    }

    private func tabItem(for tab: AppTab, systemName: String, title: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            Haptics.playLightTap()
            selectedTab = tab
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .transaction { $0.animation = nil }
                }
                VStack(spacing: 6) {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.55))
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .scaleEffect(isSelected ? pressedScale : 1.0)
        .animation(nil, value: isSelected)
    }
}
