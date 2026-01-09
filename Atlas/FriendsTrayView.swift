import SwiftUI

struct FriendsPill: View {
    var isVisible: Bool
    var onTap: () -> Void

    var body: some View {
        if isVisible {
            Button(action: {
                Haptics.playLightTap()
                onTap()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                    Text("Friends")
                        .appFont(.body, weight: .semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableGlassButtonStyle())
        }
    }
}

struct FriendsSheet: View {
    @EnvironmentObject private var authStore: AuthStore
    @ObservedObject var store: FriendsStore
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0
    @State private var usernameInput: String = ""
    @State private var friendToRemove: AtlasFriend?
    @State private var showRemoveConfirm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(AppMotion.primary) {
                        onDismiss()
                    }
                }

            NavigationStack {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    header

                    if authStore.isReadyForFriends {
                        addFriendSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if let success = store.successMessage {
                                    Text(success)
                                        .appFont(.footnote, weight: .semibold)
                                        .foregroundStyle(.green)
                                } else if let message = store.lastErrorMessage ?? store.errorMessage ?? store.uiError {
                                    Text(message)
                                        .appFont(.footnote)
                                        .foregroundStyle(.red)
                                }

                                requestsSection
                                friendsSection
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                        .frame(maxHeight: 400)
                    } else {
                        unauthenticatedState
                            .padding(.horizontal, 24)
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .background(
                    Color.black.opacity(0.9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            if value.translation.height > 80 {
                                withAnimation(AppMotion.primary) {
                                    onDismiss()
                                }
                            }
                            dragOffset = 0
                        }
                )
            }
            .navigationDestination(for: AtlasFriend.self) { friend in
                FriendDetailView(friend: friend)
            }
        }
        .confirmationDialog(
            "Remove friend?",
            isPresented: $showRemoveConfirm,
            presenting: friendToRemove
        ) { friend in
            Button(role: .destructive) {
                Task {
                    let success = await store.remove(friendIdString: friend.id)
                    if success {
                        Haptics.playLightTap()
                        friendToRemove = nil
                    }
                }
            } label: {
                Text("Remove \(friend.username.map { "@\($0)" } ?? friend.email)")
            }
            Button("Cancel", role: .cancel) {
                friendToRemove = nil
            }
        } message: { friend in
            Text("Remove \(friend.username.map { "@\($0)" } ?? friend.email) from friends?")
        }
        .task {
            if authStore.isReadyForFriends {
                await store.refreshAll()
            } else {
                store.lastErrorMessage = "Sign in to use Friends."
                store.uiError = store.lastErrorMessage
            }
        }
        .onChange(of: authStore.isReadyForFriends) { _, isReady in
            if isReady {
                Task { await store.refreshAll() }
            } else {
                store.lastErrorMessage = "Sign in to use Friends."
                store.uiError = store.lastErrorMessage
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(AppMotion.primary, value: dragOffset)
    }

    private var header: some View {
        HStack {
            Text("Friends")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
            Spacer()
            if store.isLoading {
                ProgressView()
                    .tint(.primary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var unauthenticatedState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in to use Friends")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
            Text("You need an active session to view and send requests.")
                .appFont(.body)
                .foregroundStyle(.secondary)
            Button {
                Haptics.playLightTap()
                onDismiss()
                Task { await authStore.signOut() }
            } label: {
                Text("Go to Sign In")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
            }
            .buttonStyle(PressableGlassButtonStyle())
        }
    }

    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add friend")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                TextField("username or email", text: $usernameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.default)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                Button {
                    Haptics.playLightTap()
                    let username = usernameInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard username.isEmpty == false else { return }
                    Task {
                        await store.sendRequest(username: username)
                        await MainActor.run {
                            if store.lastErrorMessage == nil && store.uiError == nil && store.errorMessage == nil {
                                usernameInput = ""
                                dismissKeyboard()
                            }
                        }
                    }
                } label: {
                    Text("Send")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(PressableGlassButtonStyle())
                .disabled(store.isLoading)
            }
        }
    }

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requests")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            if store.incomingRequests.isEmpty && store.outgoingRequests.isEmpty {
                Text("No requests")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.incomingRequests) { request in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.fromUsername.map { "@\($0)" } ?? (request.fromEmail ?? "Unknown"))
                                .appFont(.body, weight: .semibold)
                            if let date = request.createdAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                Haptics.playLightTap()
                                Task { await store.accept(requestIdString: request.id) }
                            } label: {
                                Text("Accept")
                            }
                            .buttonStyle(PressableGlassButtonStyle())
                            .disabled(store.isLoading)

                            Button {
                                Haptics.playLightTap()
                                Task { await store.decline(requestIdString: request.id) }
                            } label: {
                                Text("Decline")
                            }
                            .buttonStyle(PressableGlassButtonStyle())
                            .disabled(store.isLoading)
                        }
                    }
                }

                ForEach(store.outgoingRequests) { request in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(request.toUsername.map { "@\($0)" } ?? (request.toEmail ?? "Unknown"))
                                .appFont(.body, weight: .semibold)
                            if let date = request.createdAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("Pending")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Friends")
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.primary)
            if store.friends.isEmpty {
                Text("No friends yet")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.friends) { friend in
                    NavigationLink(value: friend) {
                        HStack {
                            Text(friend.username.map { "@\($0)" } ?? friend.email)
                                .appFont(.body, weight: .semibold)
                            Spacer()
                            if let date = friend.createdAt {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .appFont(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { Haptics.playLightTap() })
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            friendToRemove = friend
                            showRemoveConfirm = true
                        } label: {
                            Label("Remove Friend", systemImage: "person.fill.xmark")
                        }
                    }
                }
            }
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
