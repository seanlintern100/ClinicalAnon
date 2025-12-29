//
//  ConversationContext.swift
//  Redactor
//
//  Purpose: Manages conversation history and smart summarization for AI context
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Conversation Context

@MainActor
class ConversationContext: ObservableObject {

    // MARK: - Properties

    /// Full message history for the session
    @Published private(set) var messages: [ChatMessage] = []

    /// Summarized context from older messages
    @Published private(set) var contextSummary: String = ""

    /// Whether summarization is in progress
    @Published private(set) var isSummarizing: Bool = false

    // MARK: - Configuration

    /// Maximum messages before triggering summarization
    private let maxMessagesBeforeSummarization = 50

    /// Number of recent messages to keep after summarization
    private let messagesToKeepAfterSummary = 10

    /// Reference to bedrock service for summarization calls
    private weak var bedrockService: BedrockService?
    private var selectedModel: String = ""

    // MARK: - Initialization

    init() {}

    /// Configure with BedrockService for summarization
    func configure(bedrockService: BedrockService, model: String) {
        self.bedrockService = bedrockService
        self.selectedModel = model
    }

    // MARK: - Public Methods

    /// Add a message to the conversation history
    func addMessage(_ message: ChatMessage) {
        messages.append(message)

        // Check if we need to summarize
        if messages.count > maxMessagesBeforeSummarization && contextSummary.isEmpty {
            Task {
                await triggerSummarization()
            }
        }
    }

    /// Add a user message to the conversation
    func addUserMessage(_ content: String) {
        addMessage(ChatMessage.user(content))
    }

    /// Add an assistant message to the conversation
    func addAssistantMessage(_ content: String) {
        addMessage(ChatMessage.assistant(content))
    }

    /// Get messages formatted for API call
    /// Returns recent messages (after summarization threshold) plus summary in system prompt
    func getMessagesForAPI() -> [ChatMessage] {
        if messages.count <= maxMessagesBeforeSummarization {
            return messages
        }

        // Return only the most recent messages
        return Array(messages.suffix(messagesToKeepAfterSummary))
    }

    /// Build system prompt with context summary injected
    func buildSystemPrompt(basePrompt: String) -> String {
        var prompt = basePrompt

        // Inject context summary if available
        if !contextSummary.isEmpty {
            prompt += """


            ## Previous Conversation Context
            \(contextSummary)
            """
        }

        return prompt
    }

    /// Reset the conversation context (for new session/workflow)
    func reset() {
        messages.removeAll()
        contextSummary = ""
        isSummarizing = false
    }

    /// Get the total message count
    var messageCount: Int {
        messages.count
    }

    /// Check if summarization has occurred
    var hasSummary: Bool {
        !contextSummary.isEmpty
    }

    // MARK: - Private Methods

    private func triggerSummarization() async {
        guard !isSummarizing else { return }
        guard let bedrockService = bedrockService else { return }

        isSummarizing = true

        do {
            try await summarizeOlderMessages(using: bedrockService)
        } catch {
            // Summarization failed, but we continue without it
            print("Summarization failed: \(error.localizedDescription)")
        }

        isSummarizing = false
    }

    private func summarizeOlderMessages(using bedrockService: BedrockService) async throws {
        // Get messages to summarize (all except the most recent ones we'll keep)
        let messagesToSummarize = Array(messages.dropLast(messagesToKeepAfterSummary))

        guard !messagesToSummarize.isEmpty else { return }

        // Format messages for summarization
        let conversationText = messagesToSummarize.map { message in
            "\(message.role.rawValue.capitalized): \(message.content)"
        }.joined(separator: "\n\n")

        let summaryPrompt = """
        Summarize this conversation history concisely, preserving:
        - Key decisions and preferences expressed
        - Important context that should inform future responses
        - Any specific instructions or corrections given
        - Writing style preferences if mentioned

        Be concise but thorough. Focus on information that would be useful for continuing the conversation.

        Conversation:
        \(conversationText)
        """

        let systemPrompt = """
        You are a conversation summarizer. Create a concise summary that captures the essential context from this conversation. Focus on information that would help continue the conversation coherently.
        """

        // Call BedrockService to get summary
        let summary = try await bedrockService.invoke(
            systemPrompt: systemPrompt,
            userMessage: summaryPrompt,
            model: selectedModel,
            maxTokens: 1024
        )

        contextSummary = summary
    }
}

// MARK: - Convenience Extensions

extension ConversationContext {

    /// Create a snapshot of current context state
    var debugDescription: String {
        """
        ConversationContext:
        - Messages: \(messages.count)
        - Has Summary: \(hasSummary)
        - Is Summarizing: \(isSummarizing)
        - Summary Length: \(contextSummary.count) chars
        """
    }
}
