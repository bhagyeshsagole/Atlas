import SwiftUI

struct FriendDetailView: View {
    let friend: AtlasFriend

    private var title: String {
        if let username = friend.username, username.isEmpty == false {
            return "@\(username)"
        }
        return friend.email.isEmpty ? "Friend" : friend.email
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(.primary)

                GlassCard(cornerRadius: AppStyle.glassCardCornerRadiusLarge, shadowRadius: AppStyle.glassShadowRadiusPrimary) {
                    VStack(spacing: 0) {
                        row(title: "Workout History")
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                        row(title: "Calendar")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, AppStyle.screenHorizontalPadding)
            .padding(.top, 24)
        }
        .navigationTitle("Friend")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String) -> some View {
        HStack {
            Text(title)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary.opacity(0.9))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .opacity(0.7)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FriendDetailView(
            friend: AtlasFriend(
                id: UUID().uuidString,
                email: "friend@example.com",
                username: "friend",
                createdAt: Date()
            )
        )
    }
}
#endif
