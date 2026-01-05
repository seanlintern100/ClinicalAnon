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
    /// For documents under 600K chars, sends full text for accurate detection
    /// For very large documents (>600K chars), uses chunked detection with overlap
    func detectDocumentBoundaries(_ text: String) async throws -> [DetectedDocument] {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        // Very large documents (>600K chars, ~150K tokens) need chunked detection
        if text.count > 600_000 {
            #if DEBUG
            print("⚠️ Very large document (\(text.count / 1000)K chars) - using chunked detection")
            #endif
            return try await detectBoundariesChunked(text, chunkSize: 250_000, overlap: 20_000)
        }

        // Standard detection: send full text with line numbers
        #if DEBUG
        print("🔵 Document detection: analyzing \(text.count / 1000)K chars")
        #endif
        return try await detectBoundariesFullText(text)
    }

    /// Detect boundaries by sending full text to AI
    private func detectBoundariesFullText(_ text: String) async throws -> [DetectedDocument] {
        let lines = text.components(separatedBy: .newlines)

        // Add line numbers to full text for accurate boundary detection
        var numberedText = ""
        for (index, line) in lines.enumerated() {
            numberedText += "[\(index + 1)] \(line)\n"
        }

        let prompt = """
        Analyze this clinical document text and identify ALL SEPARATE DOCUMENTS within it.

        Look for document boundaries indicated by:
        - Different authors or signatures (e.g., "Dr Smith", "Signed by")
        - Document headers/titles (e.g., "REPORT", "Assessment", "Progress Notes", "Letter")
        - Different dates that indicate separate documents
        - Letterheads or organisation names
        - Clear changes in document type or format

        IMPORTANT: There may be 10, 15, or even 20+ separate documents. Find ALL of them.

        Return a JSON array with EVERY document found:
        ```json
        {
          "documents": [
            {
              "title": "GP Referral Letter",
              "author": "Dr Sarah Chen",
              "date": "12 Dec 2024",
              "type": "Referral",
              "startLine": 1,
              "endLine": 45,
              "summary": "Brief 1-2 sentence summary"
            },
            {
              "title": "Physiotherapy Assessment",
              "author": "John Smith, Physiotherapist",
              "date": "15 Dec 2024",
              "type": "Assessment",
              "startLine": 46,
              "endLine": 120,
              "summary": "Brief summary"
            }
          ]
        }
        ```

        The line numbers [N] at the start of each line indicate the line number.
        Use these to specify startLine and endLine for each document.
        If you can't determine exact boundaries, estimate based on content changes.

        Text:
        \(numberedText)
        """

        let systemPrompt = "You are a clinical document analyzer. Return valid JSON only, no other text."

        do {
            let response = try await bedrockService.invoke(
                systemPrompt: systemPrompt,
                userMessage: prompt,
                model: credentialsManager.selectedModel,
                maxTokens: 4000
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

    /// Detect boundaries in very large documents using overlapping chunks
    private func detectBoundariesChunked(_ text: String, chunkSize: Int, overlap: Int) async throws -> [DetectedDocument] {
        let lines = text.components(separatedBy: .newlines)
        var allDocuments: [DetectedDocument] = []
        var processedEndLines: Set<Int> = []

        var startLine = 0
        var chunkIndex = 0

        while startLine < lines.count {
            // Calculate chunk boundaries in lines (estimate ~100 chars per line)
            let estimatedLinesPerChunk = chunkSize / 100
            let overlapLines = overlap / 100
            let endLine = min(startLine + estimatedLinesPerChunk, lines.count)

            // Extract chunk with line numbers adjusted to original document
            var chunkText = ""
            for i in startLine..<endLine {
                chunkText += "[\(i + 1)] \(lines[i])\n"
            }

            #if DEBUG
            print("🔵 Processing chunk \(chunkIndex + 1): lines \(startLine + 1)-\(endLine)")
            #endif

            let prompt = """
            Analyze this section of a clinical document (lines \(startLine + 1) to \(endLine)) and identify ALL SEPARATE DOCUMENTS within it.

            Look for document boundaries indicated by:
            - Different authors or signatures (e.g., "Dr Smith", "Signed by")
            - Document headers/titles (e.g., "REPORT", "Assessment", "Progress Notes", "Letter")
            - Different dates that indicate separate documents
            - Letterheads or organisation names
            - Clear changes in document type or format

            Return a JSON array with EVERY document found:
            ```json
            {
              "documents": [
                {
                  "title": "Document Title",
                  "author": "Author Name",
                  "date": "Date",
                  "type": "Document Type",
                  "startLine": 1,
                  "endLine": 45,
                  "summary": "Brief 1-2 sentence summary"
                }
              ]
            }
            ```

            Use the line numbers shown [N] for startLine and endLine values.

            Text:
            \(chunkText)
            """

            let systemPrompt = "You are a clinical document analyzer. Return valid JSON only, no other text."

            do {
                let response = try await bedrockService.invoke(
                    systemPrompt: systemPrompt,
                    userMessage: prompt,
                    model: credentialsManager.selectedModel,
                    maxTokens: 4000
                )

                // Parse documents from this chunk
                let chunkDocs = parseDocumentBoundaries(response, fullText: text)

                // Add documents, avoiding duplicates from overlap regions
                for doc in chunkDocs {
                    // Extract the startLine from content position (rough check)
                    let docLines = doc.fullContent.components(separatedBy: .newlines)
                    if let firstLine = docLines.first,
                       let lineIndex = lines.firstIndex(of: firstLine) {
                        if !processedEndLines.contains(lineIndex) {
                            allDocuments.append(doc)
                            processedEndLines.insert(lineIndex + docLines.count)
                        }
                    } else {
                        // Can't determine position, add if not a duplicate by title
                        if !allDocuments.contains(where: { $0.title == doc.title && $0.author == doc.author }) {
                            allDocuments.append(doc)
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("🔴 Chunk \(chunkIndex + 1) detection failed: \(error.localizedDescription)")
                #endif
            }

            // Move to next chunk with overlap
            startLine = endLine - overlapLines
            chunkIndex += 1
        }

        // If no documents found, return whole text as single document
        if allDocuments.isEmpty {
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

        // Re-index document IDs
        return allDocuments.enumerated().map { index, doc in
            DetectedDocument(
                id: "doc_\(index)",
                title: doc.title,
                author: doc.author,
                date: doc.date,
                type: doc.type,
                summary: doc.summary,
                fullContent: doc.fullContent
            )
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
            #if DEBUG
            print("🔴 Document detection: Failed to parse JSON")
            #endif
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

        #if DEBUG
        print("🔵 Document detection: Found \(documents.count) document(s)")
        #endif

        let lines = fullText.components(separatedBy: .newlines)

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

        // Multiple documents - split by line numbers
        var detectedDocs: [DetectedDocument] = []

        for (index, doc) in documents.enumerated() {
            let title = doc["title"] as? String ?? "Document \(index + 1)"
            let author = doc["author"] as? String
            let date = doc["date"] as? String
            let type = doc["type"] as? String ?? "Unknown"
            let summary = doc["summary"] as? String ?? ""

            // Get line boundaries (1-indexed from AI, convert to 0-indexed)
            let startLine = max(0, (doc["startLine"] as? Int ?? 1) - 1)
            var endLine = (doc["endLine"] as? Int ?? lines.count) - 1

            // Ensure endLine doesn't exceed document
            endLine = min(endLine, lines.count - 1)

            // If this is the last document, extend to end of text
            if index == documents.count - 1 {
                endLine = lines.count - 1
            }

            // Extract content for this document
            let content: String
            if startLine <= endLine && startLine < lines.count {
                content = lines[startLine...endLine].joined(separator: "\n")
            } else {
                // Fallback if line numbers are invalid
                let estimatedLength = fullText.count / documents.count
                let startOffset = index * estimatedLength
                let endOffset = min((index + 1) * estimatedLength, fullText.count)
                let startIdx = fullText.index(fullText.startIndex, offsetBy: startOffset)
                let endIdx = fullText.index(fullText.startIndex, offsetBy: endOffset)
                content = String(fullText[startIdx..<endIdx])
            }

            #if DEBUG
            print("   Doc \(index): \(title) (lines \(startLine + 1)-\(endLine + 1), \(content.count) chars)")
            #endif

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
        - Read documents: view /memories/doc_0_content.md
        - Read specific lines: {"command": "view", "path": "/memories/doc_0_content.md", "view_range": [100, 200]}

        ## Large File Access
        When viewing large files, only the first 300 lines are returned by default.
        The response shows the total line count. Use view_range to access specific sections:
        - view_range: [1, 300] for lines 1-300
        - view_range: [301, 600] for lines 301-600

        ## Two-Phase Processing Protocol

        PHASE 1 - READING & EXTRACTING:
        - Read each document using the memory tool
        - IMMEDIATELY after reading each document, record key information in working_notes.md
        - Do NOT read multiple documents before extracting—you WILL lose context when pruned
        - Pattern: Read doc → Extract to notes → Read next doc → Extract → ...

        What to extract to working_notes.md:
        - Patient identifiers and dates
        - Diagnoses and clinical impressions
        - Medications (name, dose, dates, outcomes)
        - Key findings and abnormal values
        - Recommendations made
        - Any concerns or discrepancies between documents

        Your working_notes.md is your PERSISTENT MEMORY. Anything not recorded there may be lost.

        PHASE 2 - WRITING:
        - After reading all documents, you will receive a [PHASE TRANSITION] message
        - Generate the report using working_notes.md as your primary source
        - You may re-read specific documents for exact quotes or verification
        - Output ONLY the report content

        ## CRITICAL Output Rules
        - NEVER include meta-commentary like "Let me check...", "I'll start by...", "Now I'll..."
        - NEVER output planning text or status updates
        - Output ONLY the requested clinical content (report, summary, notes, etc.)
        - The first text you output should be the start of the actual report/document
        """
    }

    /// Build contextual prompt based on text input classification
    func buildContextualPrompt(basePrompt: String, textType: TextInputType) -> String {
        let sourceContext: String
        switch textType {
        case .roughNotes:
            sourceContext = """
            SOURCE CONTEXT: The user has provided their own rough clinical notes to be refined.
            These are the user's own observations that need cleaning up and formatting.
            """
        case .completedNotes:
            sourceContext = """
            SOURCE CONTEXT: The user has provided their own previous clinical notes for reference.
            These are the user's own completed notes being used as source material.
            """
        case .otherReports:
            sourceContext = """
            SOURCE CONTEXT: The documents provided are reports/documents written by OTHER people, not the user.
            These are reference materials to analyze and synthesize.
            IMPORTANT:
            - Do NOT attribute authorship to anyone from these source documents
            - Leave the report author as [Author Name] for the user to fill in
            - Names found in source documents are authors OF those documents, not the output
            """
        case .other:
            sourceContext = """
            SOURCE CONTEXT: The user has provided reference materials.
            """
        }

        return """
        \(sourceContext)

        \(basePrompt)
        """
    }

    /// Build contextual prompt for multiple source documents with individual classifications
    func buildContextualPromptForMultiDoc(basePrompt: String, sourceDocuments: [SourceDocument]) -> String {
        guard sourceDocuments.count > 1 else {
            // Single doc - use existing method
            let type = sourceDocuments.first?.textInputType ?? .otherReports
            return buildContextualPrompt(basePrompt: basePrompt, textType: type)
        }

        // Build per-document context
        var docContexts: [String] = []
        for doc in sourceDocuments {
            let typeLabel: String
            switch doc.textInputType {
            case .roughNotes:
                typeLabel = "User's rough notes"
            case .completedNotes:
                typeLabel = "User's completed notes"
            case .otherReports:
                typeLabel = "Report by another person"
            case .other:
                typeLabel = doc.textInputTypeDescription.isEmpty ? "Reference material" : doc.textInputTypeDescription
            }
            docContexts.append("- \(doc.displayName): \(typeLabel)")
        }

        let hasOtherReports = sourceDocuments.contains { $0.textInputType == .otherReports }

        var sourceContext = """
        SOURCE DOCUMENTS:
        \(docContexts.joined(separator: "\n"))

        """

        if hasOtherReports {
            sourceContext += """
            IMPORTANT for documents marked "Report by another person":
            - Do NOT attribute authorship to anyone from these source documents
            - Leave the report author as [Author Name] for the user to fill in
            - Names found are authors OF those documents, not the output author
            """
        }

        return """
        \(sourceContext)

        \(basePrompt)
        """
    }

    /// Process with memory tool - agentic loop with two-phase tracking
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
        let maxLoops = 30 // Safety limit (increased for two-phase)

        // Two-phase tracking
        var docsAccessed: Set<String> = []
        let totalDocCount = memoryStorage.documentCount
        var readingPhaseComplete = false
        var workingNotesUpdated = false
        var noteReminderInjected = false

        #if DEBUG
        print("🔵 Memory mode: Starting with \(totalDocCount) documents to read")
        #endif

        while loopCount < maxLoops {
            loopCount += 1

            #if DEBUG
            print("🔵 Memory mode loop \(loopCount) - docs accessed: \(docsAccessed.count)/\(totalDocCount)")
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
                    // Track document access and working notes updates
                    if let path = toolUse.inputDict["path"] as? String,
                       let command = toolUse.inputDict["command"] as? String {

                        // Track doc reads
                        if path.contains("/memories/doc_") && path.contains("_content.md") {
                            if let filename = path.components(separatedBy: "/").last {
                                let docId = filename.replacingOccurrences(of: "_content.md", with: "")
                                docsAccessed.insert(docId)

                                #if DEBUG
                                print("🔵 Memory mode: Accessed \(docId) - now \(docsAccessed.count)/\(totalDocCount)")
                                #endif
                            }
                        }

                        // Track working_notes updates (writes, not reads)
                        if path.contains("working_notes") &&
                           (command == "str_replace" || command == "create" || command == "insert") {
                            workingNotesUpdated = true
                            #if DEBUG
                            print("🔵 Memory mode: Working notes updated")
                            #endif
                        }
                    }

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

                    // Reminder: if 3+ docs read but no notes taken yet
                    if docsAccessed.count >= 3 && !workingNotesUpdated && !noteReminderInjected && !readingPhaseComplete {
                        noteReminderInjected = true

                        let reminderMessage = """
                        [REMINDER]
                        You have read \(docsAccessed.count) documents but have not recorded anything in working_notes.md.
                        Key information will be lost when context is pruned.
                        After reading each document, IMMEDIATELY extract and record important details to working_notes.md:
                        - Patient identifiers and dates
                        - Diagnoses and clinical impressions
                        - Key findings, medications, recommendations
                        Continue reading and extracting.
                        """

                        messages.append([
                            "role": "user",
                            "content": reminderMessage
                        ])

                        #if DEBUG
                        print("🔵 Memory mode: Injected note-taking reminder (3+ docs read, no notes)")
                        #endif
                    }

                    // Check for phase transition: all docs accessed AND notes updated
                    if docsAccessed.count >= totalDocCount && workingNotesUpdated && !readingPhaseComplete {
                        readingPhaseComplete = true

                        let transitionMessage = """
                        [PHASE TRANSITION]
                        READING PHASE COMPLETE. You have accessed all \(totalDocCount) documents and recorded key information.

                        Now proceed to WRITING PHASE:
                        - Generate the clinical report using your working_notes.md as the primary source
                        - You may re-read specific documents for exact quotes or verification
                        - Output ONLY the report content - no meta-commentary like "I'll now..." or "Let me..."
                        """

                        messages.append([
                            "role": "user",
                            "content": transitionMessage
                        ])

                        #if DEBUG
                        print("🔵 Memory mode: PHASE TRANSITION - all \(totalDocCount) docs accessed + notes updated")
                        #endif
                    }

                    // Fallback transition: all docs accessed but no notes (still need to proceed)
                    if docsAccessed.count >= totalDocCount && !workingNotesUpdated && !readingPhaseComplete && loopCount >= 15 {
                        readingPhaseComplete = true

                        let transitionMessage = """
                        [PHASE TRANSITION - FALLBACK]
                        You have accessed all \(totalDocCount) documents but working_notes.md was not updated.
                        Generate the report using the information you've gathered from recent document reads.
                        Output ONLY the report content.
                        """

                        messages.append([
                            "role": "user",
                            "content": transitionMessage
                        ])

                        #if DEBUG
                        print("🔵 Memory mode: FALLBACK TRANSITION - all docs accessed, no notes, loop \(loopCount)")
                        #endif
                    }

                    // Prune old tool exchanges to prevent payload explosion
                    // Keep: first user message + last 4 message pairs (8 messages)
                    let maxMessages = 9
                    if messages.count > maxMessages {
                        let firstMessage = messages[0]
                        let recentMessages = Array(messages.suffix(maxMessages - 1))
                        messages = [firstMessage] + recentMessages

                        #if DEBUG
                        print("🔵 Memory mode: Pruned messages to \(messages.count)")
                        #endif

                        // After pruning, inject status message if still in reading phase
                        if !readingPhaseComplete && totalDocCount > 0 {
                            let accessed = docsAccessed.sorted().joined(separator: ", ")
                            let remainingDocs = (0..<totalDocCount)
                                .map { "doc_\($0)" }
                                .filter { !docsAccessed.contains($0) }
                            let remaining = remainingDocs.joined(separator: ", ")
                            let notesStatus = workingNotesUpdated ? "YES - notes recorded" : "NO - remember to extract key info!"

                            let statusMessage: String
                            if remainingDocs.isEmpty {
                                statusMessage = """
                                [SYSTEM STATUS]
                                Documents accessed: \(accessed)
                                Working notes updated: \(notesStatus)
                                All documents accessed. \(workingNotesUpdated ? "Ready to generate report from working_notes.md." : "Extract remaining info to working_notes.md, then generate.")
                                """
                            } else {
                                statusMessage = """
                                [SYSTEM STATUS]
                                Documents accessed: \(accessed.isEmpty ? "none yet" : accessed)
                                Documents remaining: \(remaining)
                                Working notes updated: \(notesStatus)
                                Continue: Read doc → Extract to working_notes.md → Read next doc
                                """
                            }

                            messages.append([
                                "role": "user",
                                "content": statusMessage
                            ])

                            #if DEBUG
                            print("🔵 Memory mode: Injected status - \(docsAccessed.count)/\(totalDocCount) accessed, notes: \(workingNotesUpdated)")
                            #endif
                        }
                    }

                    // Safety limit: force writing phase after 25 loops
                    if loopCount >= 25 && !readingPhaseComplete {
                        readingPhaseComplete = true

                        let timeLimitMessage = """
                        [TIME LIMIT]
                        You have been processing for \(loopCount) iterations.
                        Documents accessed: \(docsAccessed.sorted().joined(separator: ", "))
                        Working notes updated: \(workingNotesUpdated ? "YES" : "NO")

                        Generate the best possible report \(workingNotesUpdated ? "using working_notes.md as your source" : "with the information gathered").
                        Output ONLY the report content - no meta-commentary.
                        """

                        messages.append([
                            "role": "user",
                            "content": timeLimitMessage
                        ])

                        #if DEBUG
                        print("🔵 Memory mode: TIME LIMIT - forcing writing phase at loop \(loopCount)")
                        #endif
                    }

                    // Continue loop
                    continue
                }
            }

            // No tool use - we're done
            if response.stopReason == "end_turn" || !response.hasToolUse {
                break
            }
        }

        #if DEBUG
        print("🔵 Memory mode: Complete after \(loopCount) loops, \(finalText.count) chars output")
        #endif

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
