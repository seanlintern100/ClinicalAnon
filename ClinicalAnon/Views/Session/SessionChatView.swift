//
//  SessionChatView.swift
//  ClinicalAnon
//
//  Purpose: Chat panel for AI assistance during live sessions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Chat View

struct SessionChatView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @ObservedObject var aiService: SessionAIService
    @State private var inputText: String = ""
    @State private var scrollProxy: ScrollViewProxy?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Messages area
            chatMessages

            Divider()

            // Input area
            chatInput
        }
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(DesignSystem.Colors.primaryTeal)

            Text("Session AI")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            // Context toggle indicator
            if aiService.includeTranscriptContext {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption)
                    Text("Context ON")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundStyle(DesignSystem.Colors.primaryTeal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.primaryTeal.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Messages

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    if session.chatMessages.isEmpty && !aiService.isProcessing {
                        emptyState
                    } else {
                        ForEach(Array(session.chatMessages.enumerated()), id: \.element.id) { index, message in
                            SessionChatMessageView(
                                message: message,
                                isLatest: index == session.chatMessages.count - 1
                            )
                            .id(message.id)
                        }

                        // Thinking indicator
                        if aiService.isProcessing {
                            thinkingIndicator
                                .id("thinking")
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(DesignSystem.Spacing.medium)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: session.chatMessages.count) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: aiService.isProcessing) { isProcessing in
                if isProcessing {
                    withAnimation {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.3))

            Text("Ask the AI about this session")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Try: \"Summarize the key points so far\"")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.7))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ProgressView()
                .scaleEffect(0.6)

            Text("Thinking...")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.leading, DesignSystem.Spacing.medium)
    }

    // MARK: - Input

    private var chatInput: some View {
        HStack(alignment: .bottom, spacing: DesignSystem.Spacing.small) {
            TextEditor(text: $inputText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .frame(minHeight: 36, maxHeight: 100)
                .fixedSize(horizontal: false, vertical: true)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .stroke(DesignSystem.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                )
                .onKeyPress { keyPress in
                    if keyPress.key == .return {
                        if keyPress.modifiers.contains(.command) {
                            inputText += "\n"
                            return .handled
                        } else {
                            if canSend {
                                sendMessage()
                            }
                            return .handled
                        }
                    }
                    return .ignored
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(canSend
                        ? DesignSystem.Colors.primaryTeal
                        : DesignSystem.Colors.textSecondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(DesignSystem.Spacing.small)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isProcessing
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        Task {
            do {
                _ = try await aiService.sendMessage(message, session: session)
            } catch {
                // Error is already stored in aiService.error
            }
        }
    }
}

// MARK: - Session Chat Message View

private struct SessionChatMessageView: View {
    let message: ChatMessage
    var isLatest: Bool = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignSystem.Spacing.xs) {
                Text(isUser ? "You" : "AI")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isUser ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)

                if isUser {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                } else {
                    // Use AttributedString for markdown in AI responses
                    Text(parseMarkdown(message.content))
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isUser
                        ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                        : DesignSystem.Colors.background)
            )

            if !isUser {
                Spacer(minLength: 40)
            }
        }
    }

    /// Parse markdown to AttributedString for basic formatting
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SessionChatView_Previews: PreviewProvider {
    static var previews: some View {
        SessionChatView(
            session: LiveSession.sample,
            aiService: SessionAIService(
                bedrockService: BedrockService(),
                credentialsManager: .shared
            )
        )
        .frame(width: 400, height: 500)
    }
}
#endif
