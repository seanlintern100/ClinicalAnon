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

    /// Memory storage for large document mode
    let memoryStorage: MemoryStorage

    private var currentTask: Task<Void, Never>?

    /// Threshold for switching to memory mode (100K chars)
    private let memoryModeThreshold = 100_000

    // MARK: - Initialization

    init(bedrockService: BedrockService, credentialsManager: AWSCredentialsManager) {
        self.bedrockService = bedrockService
        self.credentialsManager = credentialsManager
        self.context = ConversationContext()
        self.memoryStorage = MemoryStorage()

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

    // MARK: - Memory Mode

    /// Check if input should use memory mode
    func shouldUseMemoryMode(for text: String) -> Bool {
        return text.count >= memoryModeThreshold
    }

    /// Detect document boundaries in large text using AI
    func detectDocumentBoundaries(_ text: String) async throws -> [DetectedDocument] {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        // Send first ~4K chars + last ~1K chars for analysis
        let sample = String(text.prefix(4000)) + "\n\n[...]\n\n" + String(text.suffix(1000))

        let prompt = """
        Analyze this text sample from a clinical document bundle.

        Does it contain MULTIPLE SEPARATE DOCUMENTS (e.g., multiple letters, reports, or notes)?

        If YES, return a JSON array describing each document:
        ```json
        {
          "documents": [
            {
              "title": "GP Referral Letter",
              "author": "Dr Sarah Chen",
              "date": "12 Dec 2024",
              "type": "Referral",
              "starts_with": "Dear Dr Torres",
              "summary": "Brief 1-2 sentence summary"
            }
          ]
        }
        ```

        If NO (single document), return:
        ```json
        {
          "documents": [
            {
              "title": "Document title or first line",
              "author": "Author if identifiable",
              "date": "Date if found",
              "type": "Document type",
              "starts_with": null,
              "summary": "Brief summary"
            }
          ]
        }
        ```

        Text sample:
        \(sample)
        """

        let systemPrompt = "You are a clinical document analyzer. Return valid JSON only, no other text."

        do {
            let response = try await bedrockService.invoke(
                systemPrompt: systemPrompt,
                userMessage: prompt,
                model: credentialsManager.selectedModel,
                maxTokens: 2000
            )

            return parseDocumentBoundaries(response, fullText: text)
        } catch {
            // Fallback: treat as single document
            #if DEBUG
            print("🔴 Document detection failed: \(error.localizedDescription)")
            #endif
            return [DetectedDocument(
                id: "doc_0",
                title: "Document",
                author: nil,
                date: nil,
                type: "Unknown",
                summary: "",
                fullContent: text
            )]
        }
    }

    /// Parse AI response to extract document boundaries
    private func parseDocumentBoundaries(_ jsonResponse: String, fullText: String) -> [DetectedDocument] {
        // Extract JSON from response (handle markdown code blocks)
        var jsonString = jsonResponse
        if let jsonStart = jsonResponse.range(of: "{"),
           let jsonEnd = jsonResponse.range(of: "}", options: .backwards) {
            jsonString = String(jsonResponse[jsonStart.lowerBound...jsonEnd.upperBound])
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let documents = parsed["documents"] as? [[String: Any]] else {
            // Fallback: single document
            return [DetectedDocument(
                id: "doc_0",
                title: "Document",
                author: nil,
                date: nil,
                type: "Unknown",
                summary: "",
                fullContent: fullText
            )]
        }

        // If single document, return it
        if documents.count == 1 {
            let doc = documents[0]
            return [DetectedDocument(
                id: "doc_0",
                title: doc["title"] as? String ?? "Document",
                author: doc["author"] as? String,
                date: doc["date"] as? String,
                type: doc["type"] as? String ?? "Unknown",
                summary: doc["summary"] as? String ?? "",
                fullContent: fullText
            )]
        }

        // Multiple documents - split by "starts_with" markers
        var detectedDocs: [DetectedDocument] = []
        var remainingText = fullText

        for (index, doc) in documents.enumerated() {
            let title = doc["title"] as? String ?? "Document \(index + 1)"
            let author = doc["author"] as? String
            let date = doc["date"] as? String
            let type = doc["type"] as? String ?? "Unknown"
            let summary = doc["summary"] as? String ?? ""
            let startsWith = doc["starts_with"] as? String

            var content: String

            if index == documents.count - 1 {
                // Last document gets remaining text
                content = remainingText
            } else if let marker = startsWith,
                      let nextDoc = documents[safe: index + 1],
                      let nextMarker = nextDoc["starts_with"] as? String,
                      let splitRange = remainingText.range(of: nextMarker) {
                // Split at next document's marker
                content = String(remainingText[..<splitRange.lowerBound])
                remainingText = String(remainingText[splitRange.lowerBound...])
            } else {
                // Can't find marker, give rough estimate
                let estimatedLength = fullText.count / documents.count
                let endIndex = remainingText.index(
                    remainingText.startIndex,
                    offsetBy: min(estimatedLength, remainingText.count)
                )
                content = String(remainingText[..<endIndex])
                remainingText = String(remainingText[endIndex...])
            }

            detectedDocs.append(DetectedDocument(
                id: "doc_\(index)",
                title: title,
                author: author,
                date: date,
                type: type,
                summary: summary,
                fullContent: content.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return processDetectedDocuments(detectedDocs)
    }

    /// Process detected documents - chunk large single docs
    private func processDetectedDocuments(_ documents: [DetectedDocument]) -> [DetectedDocument] {
        // If we got a single large document, chunk it
        if documents.count == 1 && documents[0].fullContent.count > 50_000 {
            return splitIntoChunks(documents[0], targetSize: 30_000)
        }
        return documents
    }

    /// Split large document into chunks at paragraph boundaries
    private func splitIntoChunks(_ doc: DetectedDocument, targetSize: Int) -> [DetectedDocument] {
        var chunks: [DetectedDocument] = []
        let text = doc.fullContent

        // Split on double newlines (paragraphs)
        let paragraphs = text.components(separatedBy: "\n\n")
        var currentChunk = ""
        var chunkIndex = 0

        for para in paragraphs {
            if currentChunk.count + para.count > targetSize && !currentChunk.isEmpty {
                chunks.append(DetectedDocument(
                    id: "doc_0_chunk_\(chunkIndex)",
                    title: "\(doc.title) - Part \(chunkIndex + 1)",
                    author: doc.author,
                    date: doc.date,
                    type: doc.type,
                    summary: "",
                    fullContent: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                chunkIndex += 1
                currentChunk = para
            } else {
                currentChunk += (currentChunk.isEmpty ? "" : "\n\n") + para
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(DetectedDocument(
                id: "doc_0_chunk_\(chunkIndex)",
                title: "\(doc.title) - Part \(chunkIndex + 1)",
                author: doc.author,
                date: doc.date,
                type: doc.type,
                summary: "",
                fullContent: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return chunks
    }

    /// Generate summary for a document
    func generateDocumentSummary(_ content: String, title: String, type: String) async throws -> String {
        let truncated = String(content.prefix(8000))

        let prompt = """
        Summarize this clinical document in 2-3 sentences.
        Focus on: purpose, key findings, recommendations, important dates/values.

        Document title: \(title)
        Document type: \(type)

        Content:
        \(truncated)
        """

        let systemPrompt = "You are a clinical document summarizer. Be concise and factual. Return only the summary, no other text."

        return try await bedrockService.invoke(
            systemPrompt: systemPrompt,
            userMessage: prompt,
            model: credentialsManager.selectedModel,
            maxTokens: 200
        )
    }

    /// Build system prompt for memory mode with embedded index
    func buildMemoryModeSystemPrompt(basePrompt: String) -> String {
        let index = memoryStorage.readFile("index.md") ?? "No documents loaded"

        return """
        \(basePrompt)

        ## Document Index
        \(index)

        ## Memory System
        Full document contents are stored in /memories/doc_N_content.md files.
        Use your memory tool to:
        - Read full documents: view /memories/doc_0_content.md
        - Store observations: update /memories/working_notes.md

        ## When to Read Full Documents
        Use summaries above for overview questions and planning.
        Read full doc_N_content.md when you need:
        - Exact quotes or specific values (dates, dosages, names)
        - Details the user specifically asks about
        - Information not captured in the summary

        Read on demand—don't load all documents upfront.

        ## Working Notes Protocol
        working_notes.md has sections: Active Context, Observations, Superseded.
        Keep notes organized. Delete outdated content.
        """
    }

    /// Process with memory tool - agentic loop
    func processWithMemory(userMessage: String, systemPrompt: String) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        isProcessing = true
        error = nil
        currentOutput = ""

        defer { isProcessing = false }

        // Build enhanced system prompt with embedded index
        let enhancedPrompt = buildMemoryModeSystemPrompt(basePrompt: systemPrompt)

        // Memory tool definition
        let memoryTool: [String: Any] = [
            "type": "memory_20250818",
            "name": "memory"
        ]

        // Start with user message
        var messages: [[String: Any]] = [
            ["role": "user", "content": userMessage]
        ]

        var finalText = ""
        var loopCount = 0
        let maxLoops = 20 // Safety limit

        while loopCount < maxLoops {
            loopCount += 1

            #if DEBUG
            print("🔵 Memory mode loop \(loopCount)")
            #endif

            let response = try await bedrockService.invokeWithTools(
                systemPrompt: enhancedPrompt,
                messages: messages,
                tools: [memoryTool],
                model: credentialsManager.selectedModel,
                maxTokens: 4096
            )

            // Collect any text output
            if let text = response.text {
                finalText += text
                currentOutput = finalText
            }

            // Check if AI wants to use a tool
            if let toolUse = response.toolUse {
                if toolUse.name == "memory" {
                    // Execute memory command
                    let result = memoryStorage.handleMemoryCommand(toolUse.inputDict)

                    #if DEBUG
                    print("🔵 Memory tool result: \(result.prefix(200))...")
                    #endif

                    // Add assistant message with tool use
                    var assistantContent: [[String: Any]] = []
                    if let text = response.text, !text.isEmpty {
                        assistantContent.append(["type": "text", "text": text])
                    }
                    assistantContent.append([
                        "type": "tool_use",
                        "id": toolUse.id,
                        "name": toolUse.name,
                        "input": toolUse.inputDict
                    ])

                    messages.append([
                        "role": "assistant",
                        "content": assistantContent
                    ])

                    // Add tool result
                    messages.append([
                        "role": "user",
                        "content": [
                            [
                                "type": "tool_result",
                                "tool_use_id": toolUse.id,
                                "content": result
                            ]
                        ]
                    ])

                    // Continue loop
                    continue
                }
            }

            // No tool use - we're done
            if response.stopReason == "end_turn" || !response.hasToolUse {
                break
            }
        }

        // Record in context
        context.addUserMessage(userMessage)
        context.addAssistantMessage(finalText)

        return finalText
    }

    /// Initialize memory mode with documents
    func initializeMemoryMode(documents: [DetectedDocument]) async {
        memoryStorage.reset()
        memoryStorage.isMemoryModeActive = true

        // Create index and document files
        memoryStorage.createIndexFile(from: documents)
        memoryStorage.createDocumentFiles(from: documents)
        memoryStorage.createWorkingNotesFile()
    }

    /// Reset memory mode
    func resetMemoryMode() {
        memoryStorage.reset()
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
