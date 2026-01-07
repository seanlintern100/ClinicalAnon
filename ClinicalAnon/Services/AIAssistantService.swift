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

            return try await parseDocumentBoundaries(response, fullText: text)
        } catch {
            // Fallback: treat as single document
            #if DEBUG
            print("🔴 Document detection failed: \(error.localizedDescription)")
            #endif
            return [DetectedDocument(
                id: "doc1",
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
                let chunkDocs = try await parseDocumentBoundaries(response, fullText: text)

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
                id: "doc1",
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
    private func parseDocumentBoundaries(_ jsonResponse: String, fullText: String) async throws -> [DetectedDocument] {
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
                id: "doc1",
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
                id: "doc1",
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

        return try await processDetectedDocuments(detectedDocs)
    }

    /// Process detected documents - chunk large single docs and generate summaries
    private func processDetectedDocuments(_ documents: [DetectedDocument]) async throws -> [DetectedDocument] {
        // If we got a single large document, chunk it
        if documents.count == 1 && documents[0].fullContent.count > 50_000 {
            var chunks = splitIntoChunks(documents[0], targetSize: 30_000)

            // Generate summaries for each chunk so AI knows what's in each part
            #if DEBUG
            print("🔵 Generating summaries for \(chunks.count) chunks...")
            #endif

            for i in 0..<chunks.count {
                do {
                    let summary = try await generateDocumentSummary(
                        chunks[i].fullContent,
                        title: chunks[i].title,
                        type: chunks[i].type
                    )
                    chunks[i].summary = summary

                    #if DEBUG
                    print("   Chunk \(i + 1): \(summary.prefix(60))...")
                    #endif
                } catch {
                    #if DEBUG
                    print("🔴 Failed to generate summary for chunk \(i + 1): \(error.localizedDescription)")
                    #endif
                    // Continue with empty summary if generation fails
                }
            }

            return chunks
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
                    id: "doc1_chunk_\(chunkIndex)",
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
                id: "doc1_chunk_\(chunkIndex)",
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
        // Scale extraction depth: 10 points per 10K characters (minimum 10, maximum 50)
        let charCount = content.count
        let pointCount = max(10, min(50, (charCount / 10000) * 10 + 10))
        let targetPoints = "\(pointCount)"

        // Use more content for extraction (up to 50K chars for thorough extraction)
        let truncated = String(content.prefix(50000))

        let prompt = """
        Extract key information from this clinical document to support generation of a bio-psycho-social report.

        Document: \(title)
        Type: \(type)

        Include all clinically relevant details that would help understand the person's:
        - Medical/physical status and history
        - Psychological/cognitive functioning
        - Social circumstances and supports
        - Timeline of events and interventions
        - Professional opinions and recommendations

        Extract \(targetPoints) key points. Let the document's content guide what's important.

        IMPORTANT - Include exact wording for:
        - Formal diagnoses
        - Professional opinions and recommendations
        - Significant clinical findings
        - Any statements that might be quoted in a report

        If any information is ambiguous or unclear, flag it explicitly
        (e.g., "UNCLEAR: document mentions injury but date not specified").

        Content:
        \(truncated)
        """

        let systemPrompt = """
        You are a clinical document extractor. Extract key information as bullet points.
        Be thorough - include dates, names, diagnoses, findings, and recommendations.
        Preserve exact wording for significant clinical statements.
        Return only the bullet points, no preamble or explanation.
        """

        return try await bedrockService.invoke(
            systemPrompt: systemPrompt,
            userMessage: prompt,
            model: credentialsManager.selectedModel,
            maxTokens: 800  // Reduced from 1500 to avoid context overflow with many documents
        )
    }

    /// Check for inconsistencies across document summaries
    func checkCrossDocumentInconsistencies(_ summaries: [(docId: String, title: String, summary: String)]) async throws -> String {
        guard summaries.count > 1 else {
            return "" // No cross-document check needed for single document
        }

        let combinedSummaries = summaries.map { doc in
            """
            ### \(doc.docId): \(doc.title)
            \(doc.summary)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Review these document summaries for clinically significant contradictions:

        \(combinedSummaries)

        PRIORITY - Flag contradictions in:
        - Diagnostic opinions and formulations (e.g., different diagnoses for same presentation)
        - Clinical assessments and conclusions (e.g., conflicting cognitive/IQ findings)
        - Opinions on causation or prognosis
        - Severity ratings or functional impairment levels
        - Risk assessments (self-harm, violence)
        - Treatment recommendations that conflict

        IGNORE:
        - Date/timeline discrepancies (dates are redacted and different placeholders may represent the same date)
        - Minor factual differences that don't affect clinical opinion
        - Typos or formatting differences

        Provide up to 5 significant contradictions maximum. Only include issues that genuinely conflict and would affect clinical synthesis. Fewer is fine if there aren't 5 significant issues.
        If none found, respond with "No significant contradictions noted."
        """

        let systemPrompt = "You are a clinical psychologist reviewing source documents. Flag contradictions in clinical opinions and diagnoses that would affect report writing. Focus on conflicting professional opinions, not dates or timelines. Be specific about which documents conflict and why it matters clinically."

        let result = try await bedrockService.invoke(
            systemPrompt: systemPrompt,
            userMessage: prompt,
            model: credentialsManager.selectedModel,
            maxTokens: 800
        )

        // Only return if there are actual contradictions to flag
        if result.lowercased().contains("no significant") ||
           result.lowercased().contains("no contradictions") ||
           result.lowercased().contains("no inconsistencies") {
            return ""
        }

        return """

        ## Cross-Document Notes

        *Note: These observations may reflect natural changes over time rather than true contradictions. Consider within your broader clinical understanding of the person and context of these reports.*

        \(result)
        """
    }

    /// Generate report from summaries (no agentic loop, single call - faster, no timeout)
    func generateReport(summaries: [DetectedDocument], crossDocNotes: String, systemPrompt: String) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        isProcessing = true
        error = nil
        currentOutput = ""

        defer { isProcessing = false }

        // Build prompt with embedded summaries
        var summaryText = "# Document Summaries\n\n"
        for doc in summaries {
            summaryText += "## \(doc.id.uppercased()): \(doc.title)\n"
            summaryText += "**Type:** \(doc.type) | **Date:** \(doc.date ?? "N/A")\n\n"
            summaryText += "\(doc.summary)\n\n---\n\n"
        }

        if !crossDocNotes.isEmpty {
            summaryText += "\n\(crossDocNotes)\n"
        }

        let fullPrompt = """
        \(systemPrompt)

        \(summaryText)

        ## Report Writing Approach

        You are writing a psychology report. The summaries above contain detailed extractions from all source documents.

        CRITICAL - Synthesise, don't summarise:
        - DO NOT structure your report by source document (e.g., "Report A says... Report B says...")
        - DO organise thematically (e.g., medical history, psychological functioning, social context, recommendations)
        - Weave information from multiple sources together into cohesive sections
        - When sources agree, state the finding once with confidence
        - When sources differ, note this and use clinical judgement about what to include
        - Draw on ALL relevant information from the summaries - don't leave out important details

        The goal is a single, coherent clinical narrative that reads as original work, not a summary of summaries.

        ## Output Rules
        - Output ONLY the requested clinical content (report, summary, notes, etc.)
        - No meta-commentary like "Let me check...", "I'll start by...", "Now I'll..."
        - Start directly with the report content
        - Use redacted placeholders (e.g., [PERSON_A], [ORG_B]) as they appear in the source documents
        """

        #if DEBUG
        print("🤖 generateReport: Single call with \(summaries.count) summaries embedded")
        #endif

        // Single Bedrock call, no tool use
        let result = try await bedrockService.invoke(
            systemPrompt: fullPrompt,
            userMessage: "Generate the clinical report now.",
            model: credentialsManager.selectedModel,
            maxTokens: 8000
        )

        currentOutput = result
        return result
    }

    /// Build system prompt for memory mode with embedded summaries
    func buildMemoryModeSystemPrompt(basePrompt: String, isRefinement: Bool = false) -> String {
        let summaries = memoryStorage.readFile("index.md") ?? "No documents loaded"

        var prompt = """
        \(basePrompt)

        \(summaries)

        ## Document Access

        If you need exact quotes, specific wording, or details not in the summaries,
        use the memory tool to access full documents at /memories/doc_N_content.md

        To read a document:
        - Full document: {"command": "view", "path": "/memories/doc1_content.md"}
        - Specific lines: {"command": "view", "path": "/memories/doc1_content.md", "view_range": [100, 200]}
        """

        // Only add strict output rules for initial generation, not refinement
        if !isRefinement {
            prompt += """


        ## Report Writing Approach

        You are writing a psychology report. The summaries above contain detailed extractions from all source documents.

        CRITICAL - Synthesise, don't summarise:
        - DO NOT structure your report by source document (e.g., "Report A says... Report B says...")
        - DO organise thematically (e.g., medical history, psychological functioning, social context, recommendations)
        - Weave information from multiple sources together into cohesive sections
        - When sources agree, state the finding once with confidence
        - When sources differ, note this and use clinical judgement about what to include
        - Draw on ALL relevant information from the summaries - don't leave out important details

        The goal is a single, coherent clinical narrative that reads as original work, not a summary of summaries.

        ## Output Rules
        - Output ONLY the requested clinical content (report, summary, notes, etc.)
        - No meta-commentary like "Let me check...", "I'll start by...", "Now I'll..."
        - Start directly with the report content
        - Use redacted placeholders (e.g., [PERSON_A], [ORG_B]) as they appear in the source documents - these will be restored to actual names afterward
        """
        }

        return prompt
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
        case .sessionTranscript:
            sourceContext = """
            SOURCE CONTEXT: The user has provided a transcript from a recorded therapy session.
            This is a verbatim or near-verbatim record of dialogue between therapist and client.
            Extract and synthesize the clinical content into professional notes.
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
            case .sessionTranscript:
                typeLabel = "Session transcript"
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

    /// Process with memory tool - simplified loop for optional document lookups
    func processWithMemory(userMessage: String, systemPrompt: String, isRefinement: Bool = false) async throws -> String {
        guard bedrockService.isConfigured else {
            throw AppError.aiNotConfigured
        }

        isProcessing = true
        error = nil
        currentOutput = ""

        defer { isProcessing = false }

        // Build enhanced system prompt with embedded summaries
        // For refinement, don't add strict "output only" rules that conflict with [CONVERSATION] format
        let enhancedPrompt = buildMemoryModeSystemPrompt(basePrompt: systemPrompt, isRefinement: isRefinement)

        // Memory tool definition
        let memoryTool: [String: Any] = [
            "type": "memory_20250818",
            "name": "memory"
        ]

        // Start with user message
        var messages: [[String: Any]] = [
            ["role": "user", "content": [["type": "text", "text": userMessage]]]
        ]

        var finalText = ""
        var loopCount = 0
        let maxLoops = 20 // Reduced - AI should mostly work from summaries

        #if DEBUG
        print("🔵 Memory mode: Starting (summaries embedded, memory tool available for lookups)")
        #endif

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
                    if let path = toolUse.inputDict["path"] as? String {
                        print("🔵 Memory lookup: \(path)")
                    }
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

                    // Prune if needed - but NEVER orphan tool_results
                    let maxMessages = 10
                    if messages.count > maxMessages {
                        let firstMessage = messages[0]
                        var recentMessages = Array(messages.suffix(maxMessages - 1))

                        // If first recent message is a tool_result, include its tool_use
                        if let firstRecent = recentMessages.first,
                           let content = firstRecent["content"] as? [[String: Any]],
                           let toolResult = content.first(where: { $0["type"] as? String == "tool_result" }),
                           let toolResultId = toolResult["tool_use_id"] as? String {

                            // Find the assistant message containing this tool_use
                            let prunedRange = 1..<(messages.count - recentMessages.count)
                            for i in prunedRange.reversed() {
                                if let assistantContent = messages[i]["content"] as? [[String: Any]],
                                   assistantContent.contains(where: {
                                       $0["type"] as? String == "tool_use" && $0["id"] as? String == toolResultId
                                   }) {
                                    recentMessages.insert(messages[i], at: 0)
                                    break
                                }
                            }
                        }

                        messages = [firstMessage] + recentMessages

                        #if DEBUG
                        print("🔵 Memory mode: Pruned messages to \(messages.count)")
                        #endif
                    }

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
