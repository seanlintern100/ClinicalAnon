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
    @Published var error: AIAssistantError?

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

    /// Polish existing clinical notes (clean up grammar, structure)
    func polish(text: String) async throws -> String {
        let systemPrompt = buildPolishSystemPrompt()
        return try await process(text: text, systemPrompt: systemPrompt)
    }

    /// Generate a report from input text
    func generate(text: String, template: ReportTemplate, customPrompt: String? = nil) async throws -> String {
        let systemPrompt = buildGenerateSystemPrompt(template: template, customPrompt: customPrompt)
        return try await process(text: text, systemPrompt: systemPrompt)
    }

    /// Polish with streaming output
    func polishStreaming(text: String) -> AsyncThrowingStream<String, Error> {
        let systemPrompt = buildPolishSystemPrompt()
        return processStreaming(text: text, systemPrompt: systemPrompt)
    }

    /// Generate with streaming output
    func generateStreaming(text: String, template: ReportTemplate, customPrompt: String? = nil) -> AsyncThrowingStream<String, Error> {
        let systemPrompt = buildGenerateSystemPrompt(template: template, customPrompt: customPrompt)
        return processStreaming(text: text, systemPrompt: systemPrompt)
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

    private func process(text: String, systemPrompt: String) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AIAssistantError.notConfigured
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
            let assistantError = AIAssistantError.processingFailed(error.localizedDescription)
            self.error = assistantError
            throw assistantError
        }
    }

    private func processStreaming(text: String, systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.currentTask = Task {
                guard self.bedrockService.isConfigured else {
                    continuation.finish(throwing: AIAssistantError.notConfigured)
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
                        self.error = AIAssistantError.processingFailed(error.localizedDescription)
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - System Prompts

    private func buildPolishSystemPrompt() -> String {
        """
        You are a clinical writing assistant helping healthcare professionals improve their documentation.

        Your task is to POLISH the provided clinical notes:
        - Fix grammar, spelling, and punctuation errors
        - Improve clarity and readability
        - Maintain professional clinical tone
        - Preserve all medical information accurately
        - Keep the same general structure unless it's confusing
        - Do NOT add information that wasn't in the original
        - Do NOT remove any clinical details

        IMPORTANT: The text contains placeholder codes like [PERSON_A], [PERSON_B], [DATE_A], etc.
        These are anonymization placeholders - keep them exactly as they appear.

        Respond with ONLY the polished text. Do not include explanations or commentary.
        """
    }

    private func buildGenerateSystemPrompt(template: ReportTemplate, customPrompt: String?) -> String {
        if template == .custom, let customPrompt = customPrompt, !customPrompt.isEmpty {
            return """
            You are a clinical writing assistant helping healthcare professionals create documentation.

            CUSTOM INSTRUCTIONS:
            \(customPrompt)

            IMPORTANT: The text contains placeholder codes like [PERSON_A], [PERSON_B], [DATE_A], etc.
            These are anonymization placeholders - preserve them exactly as they appear in your output.

            Generate the requested content based on the provided notes. Use only the information given.
            """
        }

        let templateInstructions = getTemplateInstructions(template)

        return """
        You are a clinical writing assistant helping healthcare professionals create documentation.

        Your task is to GENERATE a \(template.displayName) based on the provided notes.

        \(templateInstructions)

        IMPORTANT: The text contains placeholder codes like [PERSON_A], [PERSON_B], [DATE_A], etc.
        These are anonymization placeholders - preserve them exactly as they appear in your output.

        Generate the \(template.displayName) using ONLY the information provided. Do not invent details.
        Respond with ONLY the generated document. Do not include explanations or commentary.
        """
    }

    private func getTemplateInstructions(_ template: ReportTemplate) -> String {
        switch template {
        case .progressNote:
            return """
            Structure the Progress Note with these sections as appropriate:
            - Client/Patient identification (using placeholders)
            - Date of session
            - Attendees
            - Presenting issues/concerns
            - Session content/interventions
            - Client response/observations
            - Plan/next steps
            """

        case .referralLetter:
            return """
            Structure the Referral Letter with:
            - Salutation (Dear [appropriate recipient])
            - Reason for referral
            - Relevant history
            - Current presentation
            - Specific request/recommendations
            - Your contact details placeholder
            - Professional closing
            """

        case .assessment:
            return """
            Structure the Assessment with:
            - Identifying information
            - Referral source and reason
            - Presenting problems
            - Relevant history
            - Mental status/observations
            - Assessment findings
            - Formulation/diagnosis considerations
            - Recommendations
            """

        case .discharge:
            return """
            Structure the Discharge Summary with:
            - Client/Patient identification
            - Dates of service
            - Reason for admission/referral
            - Treatment provided
            - Progress made
            - Current status
            - Follow-up recommendations
            - Discharge plan
            """

        case .custom:
            return "Follow the user's custom instructions."
        }
    }
}

// MARK: - AI Assistant Errors

enum AIAssistantError: LocalizedError {
    case notConfigured
    case processingFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI service is not configured. Please add AWS credentials in Settings."
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}
