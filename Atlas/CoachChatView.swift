import SwiftUI

struct CoachChatView: View {
    let context: MuscleCoachContext
    @State private var messages: [CoachChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        bubble(for: message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            inputBar
        }
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95).ignoresSafeArea())
        .onAppear {
            seedIntro()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(context.bucket.displayName) Coach")
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
            Text("\(context.selectedRange.rawValue) • Score \(context.score)/10")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func bubble(for message: CoachChatMessage) -> some View {
        let isAssistant = message.role == .assistant
        return HStack {
            if isAssistant {
                bubbleContent(message.text)
                Spacer()
            } else {
                Spacer()
                bubbleContent(message.text)
            }
        }
    }

    private func bubbleContent(_ text: String) -> some View {
        Text(text)
            .appFont(.body, weight: .regular)
            .foregroundStyle(.primary)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(maxWidth: 320, alignment: .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask Titan a question…", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            if isLoading {
                ProgressView()
                    .tint(.primary)
            }
            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func seedIntro() {
        let introText: String
        if context.reasons.isEmpty && context.suggestions.isEmpty {
            introText = "I don’t have enough data yet — log a few sets for \(context.bucket.displayName) and I’ll give a more precise breakdown."
        } else {
            let why = context.reasons.joined(separator: " • ")
            let suggestions = context.suggestions.joined(separator: " • ")
            introText = "Score \(context.score)/10. Why: \(why). To move toward 10/10: \(suggestions)"
        }
        messages = [
            CoachChatMessage(role: .assistant, text: introText)
        ]
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let userMessage = CoachChatMessage(role: .user, text: trimmed)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        Task {
            let reply = try? await CoachChatService.reply(to: trimmed, context: context)
            await MainActor.run {
                if let reply {
                    messages.append(CoachChatMessage(role: .assistant, text: reply))
                }
                isLoading = false
            }
        }
    }
}
