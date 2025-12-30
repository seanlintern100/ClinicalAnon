//
//  AIAssistantService.swift
//  Redactor
//
//  Purpose: Orchestrates AI operations for polishing and generating clinical notes
//  Organization: 3 Big Things
//

import Foundation

// MARK: - AI Assistant Service

@MainActor
class AIAssistantService: ObservableObject {

    // MARK: - Properties

    @Published var isProcessing: Bool = false
    @Published var currentOutput: String = ""
    @Published var error: AppError?

    private let bedrockService: BedrockService
    private let credentialsManager: AWSCredentialsManager

    /// Conversation context for maintaining message history
    let context: ConversationContext

    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    init(bedrockService: BedrockService, credentialsManager: AWSCredentialsManager) {
        self.bedrockService = bedrockService
        self.credentialsManager = credentialsManager
        self.context = ConversationContext()

        // Configure context with bedrock service for summarization
        context.configure(bedrockService: bedrockService, model: credentialsManager.selectedModel)
    }

    // MARK: - Public Methods

    /// Process text with a custom prompt (streaming)
    func processStreaming(text: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        return processStreamingInternal(text: text, systemPrompt: prompt)
    }

    /// Process text with a custom prompt (non-streaming)
    func process(text: String, prompt: String) async throws -> String {
        return try await processInternal(text: text, systemPrompt: prompt)
    }

    /// Cancel the current operation
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }

    /// Reset the conversation context (for new session/workflow)
    func resetContext() {
        context.reset()
    }

    /// Record the assistant's response in context (call after streaming completes)
    func recordAssistantResponse(_ response: String) {
        context.addAssistantMessage(response)
    }

    // MARK: - Private Processing

    private func processInternal(text: String, systemPrompt: String) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        isProcessing = true
        error = nil
        currentOutput = ""

        defer { isProcessing = false }

        // Add user message to context
        context.addUserMessage(text)

        // Build system prompt with context summary
        let enhancedSystemPrompt = context.buildSystemPrompt(basePrompt: systemPrompt)

        // Get messages for API (handles summarization threshold)
        let messages = context.getMessagesForAPI()

        do {
            let result = try await bedrockService.invoke(
                systemPrompt: enhancedSystemPrompt,
                messages: messages,
                model: credentialsManager.selectedModel
            )

            // Record assistant response in context
            context.addAssistantMessage(result)

            currentOutput = result
            return result

        } catch {
            let appError = AppError.aiProcessingFailed(error.localizedDescription)
            self.error = appError
            throw appError
        }
    }

    private func processStreamingInternal(text: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.currentTask = Task {
                guard self.bedrockService.isConfigured else {
                    continuation.finish(throwing: AppError.aiNotConfigured)
                    return
                }

                await MainActor.run {
                    self.isProcessing = true
                    self.error = nil
                    self.currentOutput = ""

                    // Add user message to context
                    self.context.addUserMessage(text)
                }

                // Build system prompt with context summary
                let enhancedSystemPrompt = await MainActor.run {
                    self.context.buildSystemPrompt(basePrompt: systemPrompt)
                }

                // Get messages for API (handles summarization threshold)
                let messages = await MainActor.run {
                    self.context.getMessagesForAPI()
                }

                do {
                    let stream = self.bedrockService.invokeStreaming(
                        systemPrompt: enhancedSystemPrompt,
                        messages: messages,
                        model: self.credentialsManager.selectedModel
                    )

                    var fullResponse = ""

                    for try await chunk in stream {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        fullResponse += chunk
                        await MainActor.run {
                            self.currentOutput += chunk
                        }
                        continuation.yield(chunk)
                    }

                    // Record the complete assistant response in context
                    await MainActor.run {
                        self.context.addAssistantMessage(fullResponse)
                        self.isProcessing = false
                    }
                    continuation.finish()

                } catch {
                    await MainActor.run {
                        self.isProcessing = false
                        self.error = AppError.aiProcessingFailed(error.localizedDescription)
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
