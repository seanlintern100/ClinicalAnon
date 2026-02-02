//
//  SessionAIService.swift
//  ClinicalAnon
//
//  Purpose: AI chat service for live session assistance
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Session AI Service

@MainActor
class SessionAIService: ObservableObject {

    // MARK: - Published State

    @Published var includeTranscriptContext: Bool = true
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var error: AppError?

    // MARK: - Dependencies

    private let bedrockService: BedrockService
    private let credentialsManager: AWSCredentialsManager

    // MARK: - Constants

    private let maxContextTokens = 10000
    private let tokensPerWord = 1.3

    // MARK: - System Prompt

    private let systemPrompt = """
    You are a clinical psychology AI assistant helping a clinician during a therapy session.

    Your role is to:
    - Provide therapeutic insights and suggestions
    - Summarize key points from the conversation
    - Suggest relevant questions or approaches
    - Maintain professional clinical language

    Important:
    - All client information has been redacted (shown as [CLIENT_A], [DATE_A], etc.)
    - Never attempt to guess or reveal redacted information
    - Focus on therapeutic content, not identifying details
    """

    // MARK: - Initialization

    init(bedrockService: BedrockService, credentialsManager: AWSCredentialsManager) {
        self.bedrockService = bedrockService
        self.credentialsManager = credentialsManager
    }

    // MARK: - Public Methods

    /// Send a message to the AI and get a response
    func sendMessage(_ message: String, session: LiveSession) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        isProcessing = true
        error = nil

        defer { isProcessing = false }

        // Add user message to conversation context
        session.conversationContext.addUserMessage(message)

        // Build system prompt with optional transcript context
        var fullSystemPrompt = systemPrompt

        if includeTranscriptContext {
            let transcriptContext = prepareTranscriptContext(for: session)
            if !transcriptContext.isEmpty {
                fullSystemPrompt += """

                ## Current Session Transcript

                \(transcriptContext)
                """
            }
        }

        // Get messages for API
        let messages = session.conversationContext.getMessagesForAPI()

        do {
            let response = try await bedrockService.invoke(
                systemPrompt: fullSystemPrompt,
                messages: messages,
                model: credentialsManager.selectedModel,
                maxTokens: 2048
            )

            // Record assistant response in context
            session.conversationContext.addAssistantMessage(response)

            // Add to session's chat messages for UI
            session.chatMessages.append(ChatMessage.user(message))
            session.chatMessages.append(ChatMessage.assistant(response))

            return response

        } catch {
            let appError = AppError.aiProcessingFailed(error.localizedDescription)
            self.error = appError
            throw appError
        }
    }

    /// Prepare transcript context with token truncation
    func prepareTranscriptContext(for session: LiveSession) -> String {
        guard !session.transcriptSegments.isEmpty else {
            return ""
        }

        let transcript = session.redactedTranscript
        let wordCount = transcript.split(separator: " ").count
        let estimatedTokens = Int(Double(wordCount) * tokensPerWord)

        if estimatedTokens <= maxContextTokens {
            return transcript
        }

        // Truncate: keep most recent segments
        var accumulated: [TranscriptSegment] = []
        var tokenCount = 0

        for segment in session.transcriptSegments.reversed() {
            let segmentWordCount = segment.text.split(separator: " ").count
            let segmentTokens = Int(Double(segmentWordCount) * tokensPerWord)

            if tokenCount + segmentTokens > maxContextTokens {
                break
            }

            accumulated.insert(segment, at: 0)
            tokenCount += segmentTokens
        }

        let truncatedTranscript = accumulated.map { segment in
            "[\(segment.speaker.label)] \(segment.text)"
        }.joined(separator: "\n\n")

        return "[Earlier content truncated]\n\n" + truncatedTranscript
    }

    /// Reset the conversation context
    func resetContext(for session: LiveSession) {
        session.conversationContext.reset()
        session.chatMessages.removeAll()
    }
}
