//
//  ImprovePhaseState.swift
//  Redactor
//
//  Purpose: Manages state for the Improve phase of the workflow
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Streaming Destination

/// Where streaming AI output should be displayed
enum StreamingDestination {
    case unknown    // Not yet determined
    case document   // Stream to document pane (left)
    case chat       // Stream to chat pane (right)
}

// MARK: - Improve Phase State

/// State management for the Improve (AI processing) phase
@MainActor
class ImprovePhaseState: ObservableObject {

    // MARK: - Document Type Selection

    @Published var selectedDocumentType: DocumentType? = DocumentType.notes
    @Published var sliderSettings: SliderSettings = SliderSettings()
    @Published var customInstructions: String = ""

    // MARK: - AI Output

    @Published var aiOutput: String = ""
    @Published var isAIProcessing: Bool = false
    @Published var aiError: String?

    // MARK: - Refinement Mode

    @Published var isInRefinementMode: Bool = false
    @Published var isChatMode: Bool = false  // True when user clicked Chat button (freeform mode)
    @Published var refinementInput: String = ""
    @Published var chatHistory: [(role: String, content: String)] = []
    @Published var streamingDestination: StreamingDestination = .unknown

    // MARK: - Document State

    @Published var currentDocument: String = ""
    @Published var previousDocument: String = ""
    @Published var changedLineIndices: Set<Int> = []

    // Track what redacted text was used for AI generation
    private var lastProcessedRedactedText: String = ""

    // MARK: - Multi-Document Support

    @Published var sourceDocuments: [SourceDocument] = []
    @Published var selectedDocumentId: UUID?  // For preview in sidebar

    var selectedDocument: SourceDocument? {
        sourceDocuments.first { $0.id == selectedDocumentId }
    }

    // MARK: - Memory Mode (Large Documents)

    @Published var isMemoryMode: Bool = false
    @Published var detectedDocuments: [DetectedDocument] = []
    @Published var isDetectingDocuments: Bool = false
    @Published var memoryModeInitialized: Bool = false
    @Published var crossDocumentNotes: String = "" // Inconsistencies to display in chat

    // MARK: - Sheet States

    @Published var showPromptEditor: Bool = false
    @Published var showAddCustomCategory: Bool = false
    @Published var documentTypeToEdit: DocumentType?

    // MARK: - Services

    private let aiService: AIAssistantService
    private var currentAITask: Task<Void, Never>?

    // Callback to get current redacted text
    var getRedactedText: (() -> String)?

    // Callback to get text input type classification
    var getTextInputType: (() -> TextInputType)?

    // MARK: - Initialization

    init(aiService: AIAssistantService) {
        self.aiService = aiService
    }

    // MARK: - Computed Properties

    /// Whether Continue button should be enabled
    var canContinue: Bool {
        !aiOutput.isEmpty && !isAIProcessing
    }

    /// Whether AI has generated output
    var hasGeneratedOutput: Bool {
        !chatHistory.isEmpty || (!aiOutput.isEmpty && !isAIProcessing)
    }

    /// Whether the redacted input has changed since AI generation
    var inputChangedSinceGeneration: Bool {
        guard let getText = getRedactedText else { return false }
        return hasGeneratedOutput && lastProcessedRedactedText != getText()
    }

    /// Format all source documents for AI prompt
    func formatSourceDocumentsForAI() -> String {
        sourceDocuments.map { doc in
            """
            === \(doc.name)\(doc.description.isEmpty ? "" : " (\(doc.description))") ===

            \(doc.redactedText)
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - Actions

    /// Start chat mode - enables freeform conversation without template
    func startChatMode() {
        isChatMode = true
        isInRefinementMode = true
    }

    /// Process text with AI using selected document type
    func processWithAI() {
        #if false  // DEBUG disabled for perf testing
        print("🤖 processWithAI called")
        #endif

        guard let getText = getRedactedText else {
            #if false  // DEBUG disabled for perf testing
            print("🔴 processWithAI: getRedactedText callback is nil")
            #endif
            aiError = "No text provider configured"
            return
        }

        let inputForAI = getText()
        guard !inputForAI.isEmpty else {
            #if false  // DEBUG disabled for perf testing
            print("🔴 processWithAI: inputForAI is empty")
            #endif
            aiError = "No redacted text to process"
            return
        }

        guard let docType = selectedDocumentType else {
            #if false  // DEBUG disabled for perf testing
            print("🔴 processWithAI: selectedDocumentType is nil")
            #endif
            aiError = "No document type selected"
            return
        }

        #if false  // DEBUG disabled for perf testing
        print("🤖 AI Processing: Starting...")
        print("   Document type: \(docType.name) (id: \(docType.id))")
        print("   Input length: \(inputForAI.count) chars")
        #endif

        currentAITask?.cancel()
        aiService.cancel()

        aiOutput = ""
        aiError = nil
        isAIProcessing = true
        chatHistory = []
        isChatMode = false  // Reset chat mode when using template generation

        lastProcessedRedactedText = inputForAI
        previousDocument = ""
        changedLineIndices = []
        currentDocument = ""

        var docTypeWithInstructions = docType
        docTypeWithInstructions.customInstructions = customInstructions
        let basePrompt = docTypeWithInstructions.buildPrompt(with: sliderSettings)

        // Wrap with contextual prompt based on source documents
        let fullPrompt: String
        if sourceDocuments.count > 1 {
            // Multiple docs - use per-document classifications
            fullPrompt = aiService.buildContextualPromptForMultiDoc(basePrompt: basePrompt, sourceDocuments: sourceDocuments)
            #if false  // DEBUG disabled for perf testing
            print("   Multi-doc mode: \(sourceDocuments.count) documents with individual classifications")
            #endif
        } else {
            // Single doc - use global classification
            let textType = getTextInputType?() ?? .otherReports
            fullPrompt = aiService.buildContextualPrompt(basePrompt: basePrompt, textType: textType)
            #if false  // DEBUG disabled for perf testing
            print("   Text input type: \(textType.rawValue)")
            #endif
        }

        #if false  // DEBUG disabled for perf testing
        print("   Prompt length: \(fullPrompt.count) chars")
        print("   Prompt preview: \(String(fullPrompt.prefix(200)))...")
        #endif

        // Check if we should use memory mode:
        // 1. Large documents (exceeds character threshold)
        // 2. Multiple source documents (always use memory mode for proper separation)
        let hasMultipleDocs = sourceDocuments.count > 1
        let isLargeDocument = aiService.shouldUseMemoryMode(for: inputForAI)

        if hasMultipleDocs || isLargeDocument {
            #if false  // DEBUG disabled for perf testing
            if hasMultipleDocs {
                print("🤖 Multiple source documents (\(sourceDocuments.count)) - using memory mode")
            } else {
                print("🤖 Input exceeds threshold - switching to memory mode")
            }
            #endif
            isMemoryMode = true
            currentAITask = Task {
                await processWithMemoryMode(inputForAI, prompt: fullPrompt)
            }
            return
        }

        // Standard processing for smaller documents
        isMemoryMode = false
        currentAITask = Task {
            do {
                #if false  // DEBUG disabled for perf testing
                print("🤖 AI Processing: Starting stream...")
                #endif

                let stream = aiService.processStreaming(text: inputForAI, prompt: fullPrompt)

                var chunkCount = 0
                for try await chunk in stream {
                    if Task.isCancelled {
                        #if false  // DEBUG disabled for perf testing
                        print("🤖 AI Processing: Cancelled after \(chunkCount) chunks")
                        #endif
                        break
                    }
                    aiOutput += chunk
                    chunkCount += 1
                }

                #if false  // DEBUG disabled for perf testing
                print("🤖 AI Processing: Stream complete - \(chunkCount) chunks, \(aiOutput.count) chars")
                #endif

                // Check if AI responded with a question instead of a document
                let conversationMarker = "[CONVERSATION]"
                if aiOutput.hasPrefix(conversationMarker) {
                    // AI asked a question - route to chat instead of document
                    let cleanedOutput = String(aiOutput.dropFirst(conversationMarker.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    chatHistory.append((role: "assistant", content: cleanedOutput))
                    isInRefinementMode = true
                    // Don't set currentDocument - leave it empty so chat shows
                } else {
                    // Normal document generation
                    currentDocument = aiOutput
                    isInRefinementMode = true
                    chatHistory.append((role: "assistant", content: "[[DOCUMENT_GENERATED]]"))
                }
                isAIProcessing = false
            } catch {
                #if false  // DEBUG disabled for perf testing
                print("🤖 AI Processing: ERROR - \(error.localizedDescription)")
                #endif
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                    isAIProcessing = false
                }
            }
        }
    }

    /// Process large documents with memory mode
    private func processWithMemoryMode(_ text: String, prompt: String) async {
        do {
            isDetectingDocuments = true

            // Different handling based on source document count
            let largeDocThreshold = 100_000  // Same as memoryModeThreshold

            if sourceDocuments.count > 1 {
                // Multiple source documents: Check each for sub-document detection
                #if false  // DEBUG disabled for perf testing
                print("🤖 Memory Mode: Processing \(sourceDocuments.count) source documents")
                #endif

                var allDetectedDocs: [DetectedDocument] = []
                var docIndex = 0

                for source in sourceDocuments {
                    if source.redactedText.count >= largeDocThreshold {
                        // Large doc - detect sub-documents within it
                        #if false  // DEBUG disabled for perf testing
                        print("🤖 Memory Mode: Source '\(source.displayName)' is large (\(source.redactedText.count / 1000)K) - detecting sub-docs")
                        #endif

                        var subDocs = try await aiService.detectDocumentBoundaries(source.redactedText)

                        // Tag each sub-doc with parent source and update IDs
                        for i in 0..<subDocs.count {
                            subDocs[i].sourceDocumentId = source.id
                            subDocs[i] = DetectedDocument(
                                id: "doc\(docIndex + 1)",
                                title: subDocs[i].title,
                                author: subDocs[i].author,
                                date: subDocs[i].date,
                                type: subDocs[i].type,
                                summary: subDocs[i].summary,
                                fullContent: subDocs[i].fullContent,
                                sourceDocumentId: source.id
                            )
                            docIndex += 1
                        }

                        // Generate detailed summaries for all sub-docs
                        for i in 0..<subDocs.count {
                            let summary = try await aiService.generateDocumentSummary(
                                subDocs[i].fullContent,
                                title: subDocs[i].title,
                                type: subDocs[i].type
                            )
                            subDocs[i].summary = summary
                        }

                        allDetectedDocs.append(contentsOf: subDocs)

                        #if false  // DEBUG disabled for perf testing
                        print("🤖 Memory Mode: Found \(subDocs.count) sub-docs in '\(source.displayName)'")
                        #endif

                    } else {
                        // Small doc - use directly as single DetectedDocument
                        docIndex += 1
                        let doc = DetectedDocument(
                            id: "doc\(docIndex)",
                            title: source.displayName,
                            author: nil,
                            date: nil,
                            type: source.textInputType.rawValue,
                            summary: source.description.isEmpty ? "Source document" : source.description,
                            fullContent: source.redactedText,
                            sourceDocumentId: source.id
                        )

                        // Generate summary
                        var docWithSummary = doc
                        let summary = try await aiService.generateDocumentSummary(
                            doc.fullContent,
                            title: doc.title,
                            type: doc.type
                        )
                        docWithSummary.summary = summary

                        allDetectedDocs.append(docWithSummary)

                        #if false  // DEBUG disabled for perf testing
                        print("🤖 Memory Mode: Using '\(source.displayName)' directly (small doc)")
                        #endif
                    }
                }

                detectedDocuments = allDetectedDocs

            } else {
                // Single large document: Run AI detection to find sub-documents
                #if false  // DEBUG disabled for perf testing
                print("🤖 Memory Mode: Detecting documents within single source...")
                #endif

                detectedDocuments = try await aiService.detectDocumentBoundaries(text)

                #if false  // DEBUG disabled for perf testing
                print("🤖 Memory Mode: Detected \(detectedDocuments.count) document(s)")
                #endif

                // Tag detected documents with source document ID
                if let sourceId = sourceDocuments.first?.id {
                    for i in 0..<detectedDocuments.count {
                        detectedDocuments[i].sourceDocumentId = sourceId
                    }
                }

                // Generate detailed summaries for all documents
                // (detection returns brief summaries, we need full bullet-point extraction)
                for i in 0..<detectedDocuments.count {
                    let summary = try await aiService.generateDocumentSummary(
                        detectedDocuments[i].fullContent,
                        title: detectedDocuments[i].title,
                        type: detectedDocuments[i].type
                    )
                    detectedDocuments[i].summary = summary

                    #if false  // DEBUG disabled for perf testing
                    print("🤖 Memory Mode: Generated summary for \(detectedDocuments[i].title)")
                    #endif
                }
            }

            isDetectingDocuments = false

            // Initialize memory storage
            await aiService.initializeMemoryMode(documents: detectedDocuments)
            memoryModeInitialized = true

            #if false  // DEBUG disabled for perf testing
            print("🤖 Memory Mode: Memory storage initialized with \(detectedDocuments.count) documents")
            #endif

            // Check for cross-document inconsistencies (display in chat, not in prompt)
            if detectedDocuments.count > 1 {
                let summariesForCheck = detectedDocuments.map { doc in
                    (docId: doc.id.uppercased(), title: doc.title, summary: doc.summary)
                }
                let inconsistencies = try await aiService.checkCrossDocumentInconsistencies(summariesForCheck)
                if !inconsistencies.isEmpty {
                    crossDocumentNotes = inconsistencies
                    // Add to chat as a system note
                    chatHistory.append((role: "system", content: "⚠️ **Cross-Document Notes**\n\(inconsistencies.replacingOccurrences(of: "## Cross-Document Notes", with: "").trimmingCharacters(in: .whitespacesAndNewlines))"))

                    #if false  // DEBUG disabled for perf testing
                    print("🤖 Memory Mode: Found cross-document inconsistencies - flagged in chat")
                    #endif
                }
            }

            // Generate report directly (no agentic loop - faster, avoids timeout)
            // Refinements will use processWithMemory for document lookups
            let result = try await aiService.generateReport(
                summaries: detectedDocuments,
                crossDocNotes: crossDocumentNotes,
                systemPrompt: prompt
            )

            aiOutput = result

            // Check if AI responded with a question instead of a document
            let conversationMarker = "[CONVERSATION]"
            if result.hasPrefix(conversationMarker) {
                // AI asked a question - route to chat instead of document
                let cleanedOutput = String(result.dropFirst(conversationMarker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                chatHistory.append((role: "assistant", content: cleanedOutput))
                isInRefinementMode = true
            } else {
                // Normal document generation
                currentDocument = result
                isInRefinementMode = true
                chatHistory.append((role: "assistant", content: "[[DOCUMENT_GENERATED]]"))
            }
            isAIProcessing = false

            #if false  // DEBUG disabled for perf testing
            print("🤖 Memory Mode: Processing complete - \(result.count) chars")
            #endif

        } catch {
            #if false  // DEBUG disabled for perf testing
            print("🤖 Memory Mode: ERROR - \(error.localizedDescription)")
            #endif
            if !Task.isCancelled {
                aiError = error.localizedDescription
                isDetectingDocuments = false
                isAIProcessing = false
            }
        }
    }

    /// Send refinement request to improve the current output
    func sendRefinement() {
        let request = refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        // If this is the first message in chat mode, send with full document context
        if chatHistory.isEmpty && isChatMode {
            sendFirstChatMessage(request)
            return
        }

        guard !aiOutput.isEmpty else { return }

        chatHistory.append((role: "user", content: request))
        refinementInput = ""

        currentAITask?.cancel()
        aiService.cancel()

        aiError = nil
        isAIProcessing = true

        previousDocument = currentDocument
        changedLineIndices = []

        // Use memory mode if active
        if isMemoryMode && memoryModeInitialized {
            currentAITask = Task {
                await sendRefinementWithMemory(request)
            }
            return
        }

        // Standard refinement mode
        let docSnapshot = currentDocument
        let userMessage = """
            Here is the current document:

            ---
            \(docSnapshot)
            ---

            User request: \(request)

            If this is an editing request, return the full updated document only.
            If this is a question or discussion, respond conversationally.
            """

        let systemPrompt = """
            You are a clinical writing assistant helping refine a document.

            RESPONSE FORMAT - THIS IS CRITICAL:

            There are exactly TWO response types. You MUST choose correctly:

            1. CONVERSATION RESPONSE (for questions, clarifications, suggestions, discussions):
               - Start with exactly: [CONVERSATION]
               - Then provide your conversational reply
               - Use this for: questions, explanations, asking for clarification, discussing options, giving advice
               - Example triggers: "what", "why", "how", "can you explain", "what do you think", "should I"

            2. DOCUMENT UPDATE (for edits, rewrites, additions to the document):
               - Return ONLY the complete updated document text
               - NO prefix, NO preamble, NO "Here's the updated document:"
               - The very first character must be the start of the document content
               - Use this for: "make it shorter", "add X", "rewrite Y", "fix Z", "expand the section on"

            EXAMPLES:
            - "What are the risks?" -> [CONVERSATION] The main risks include...
            - "Make it shorter" -> [Direct document text starting immediately]
            - "Can you explain why you chose that wording?" -> [CONVERSATION] I chose that...
            - "Add more detail about the procedure" -> [Full document with expanded procedure section]
            - "Is this appropriate for a specialist?" -> [CONVERSATION] Yes, this level of detail...
            - "Rewrite the conclusion" -> [Full document with new conclusion]

            WRONG (never do this):
            - "Here's the updated document:" followed by content
            - "I've made the changes:" followed by content
            - Starting document updates with any explanation
            - Forgetting [CONVERSATION] prefix for conversational replies

            When in doubt: If the user is asking you to DO something to the document, return the document.
            If the user is asking you to EXPLAIN or DISCUSS something, use [CONVERSATION].
            """

        streamingDestination = .unknown

        currentAITask = Task {
            do {
                aiOutput = ""
                let conversationMarker = "[CONVERSATION]"

                let stream = aiService.processStreaming(text: userMessage, prompt: systemPrompt)

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    aiOutput += chunk

                    if streamingDestination == .unknown && aiOutput.count >= conversationMarker.count {
                        if aiOutput.hasPrefix(conversationMarker) {
                            streamingDestination = .chat
                            aiOutput = String(aiOutput.dropFirst(conversationMarker.count))
                            aiOutput = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            streamingDestination = .document
                        }
                    }
                }

                if streamingDestination == .document {
                    currentDocument = aiOutput
                    changedLineIndices = computeChangedLines(from: previousDocument, to: aiOutput)
                    chatHistory.append((role: "assistant", content: "[[DOCUMENT_UPDATED]]"))
                } else {
                    chatHistory.append((role: "assistant", content: aiOutput))
                }

                streamingDestination = .unknown
                isAIProcessing = false
            } catch {
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                    isAIProcessing = false
                }
            }
        }
    }

    /// Send first message in chat mode with full document context
    private func sendFirstChatMessage(_ userMessage: String) {
        guard let getText = getRedactedText else {
            aiError = "No text provider configured"
            return
        }

        let inputForAI = getText()
        guard !inputForAI.isEmpty else {
            aiError = "No redacted text to process"
            return
        }

        chatHistory.append((role: "user", content: userMessage))
        refinementInput = ""

        currentAITask?.cancel()
        aiService.cancel()

        aiError = nil
        isAIProcessing = true
        aiOutput = ""
        currentDocument = ""
        previousDocument = ""
        changedLineIndices = []

        // Build document context
        let documentContext: String
        if sourceDocuments.count > 1 {
            documentContext = formatSourceDocumentsForAI()
        } else {
            documentContext = inputForAI
        }

        let fullMessage = """
            Here is the clinical text to work with:

            ---
            \(documentContext)
            ---

            User's instructions: \(userMessage)
            """

        let systemPrompt = """
            You are a clinical writing assistant. The user will provide clinical text and their instructions.

            RESPONSE FORMAT - THIS IS CRITICAL:

            1. CONVERSATION RESPONSE (for questions, clarifications, discussing the content):
               - Start with exactly: [CONVERSATION]
               - Then provide your conversational reply

            2. DOCUMENT OUTPUT (for generating, rewriting, or transforming content):
               - Return ONLY the document text
               - NO prefix, NO preamble
               - The very first character must be the start of the content

            CRITICAL RULES:
            - Placeholders like [PERSON_A], [DATE_A], [ORG_B] must be preserved exactly as written
            - Do not invent or assume details not in the source text
            - Do not reveal or reference the original identifiers behind placeholders
            """

        streamingDestination = .unknown

        currentAITask = Task {
            do {
                let conversationMarker = "[CONVERSATION]"
                let stream = aiService.processStreaming(text: fullMessage, prompt: systemPrompt)

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    aiOutput += chunk

                    if streamingDestination == .unknown && aiOutput.count >= conversationMarker.count {
                        if aiOutput.hasPrefix(conversationMarker) {
                            streamingDestination = .chat
                            aiOutput = String(aiOutput.dropFirst(conversationMarker.count))
                            aiOutput = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            streamingDestination = .document
                        }
                    }
                }

                if streamingDestination == .document {
                    currentDocument = aiOutput
                    chatHistory.append((role: "assistant", content: "[[DOCUMENT_GENERATED]]"))
                } else {
                    chatHistory.append((role: "assistant", content: aiOutput))
                }

                streamingDestination = .unknown
                isAIProcessing = false
            } catch {
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                    isAIProcessing = false
                }
            }
        }
    }

    /// Send refinement using memory mode
    private func sendRefinementWithMemory(_ request: String) async {
        let systemPrompt = """
            You are a clinical writing assistant helping refine a document.

            The user has already received a generated document. Now they are requesting changes or asking questions.

            RESPONSE FORMAT - THIS IS CRITICAL:

            There are exactly TWO response types. You MUST choose correctly:

            1. CONVERSATION RESPONSE (for questions, clarifications, suggestions, discussions):
               - Start with exactly: [CONVERSATION]
               - Then provide your conversational reply
               - Use this for: questions, explanations, asking for clarification, discussing options, giving advice
               - Example triggers: "what", "why", "how", "can you explain", "what do you think", "should I"

            2. DOCUMENT UPDATE (for edits, rewrites, additions to the document):
               - Return ONLY the complete updated document text
               - NO prefix, NO preamble, NO "Here's the updated document:"
               - The very first character must be the start of the document content
               - Use this for: "make it shorter", "add X", "rewrite Y", "fix Z", "expand the section on"

            EXAMPLES:
            - "What are the risks?" -> [CONVERSATION] The main risks include...
            - "Make it shorter" -> [Direct document text starting immediately]
            - "Can you explain why you chose that wording?" -> [CONVERSATION] I chose that...
            - "Add more detail about the procedure" -> [Full document with expanded procedure section]
            - "Is this appropriate for a specialist?" -> [CONVERSATION] Yes, this level of detail...
            - "Rewrite the conclusion" -> [Full document with new conclusion]

            WRONG (never do this):
            - "Here's the updated document:" followed by content
            - "I've made the changes:" followed by content
            - Starting document updates with any explanation
            - Forgetting [CONVERSATION] prefix for conversational replies

            When in doubt: If the user is asking you to DO something to the document, return the document.
            If the user is asking you to EXPLAIN or DISCUSS something, use [CONVERSATION].

            MEMORY TOOL USAGE - BE EFFICIENT:

            You have:
            - The current document (being refined)
            - Summaries of all source documents (embedded in context)
            - Access to full source documents via memory tool IF NEEDED

            For simple edits (grammar, formatting, tone, restructuring, paragraph changes):
            - Just make the edit directly. Do NOT use the memory tool.

            For requests needing source information (add detail from original, check what report said):
            - Check the summaries to identify which specific document has the info
            - Use memory tool to read ONLY that specific document
            - Stop reading once you have what you need

            Do NOT read all documents for every request. Most refinements need zero memory lookups.
            """

        // Build recent conversation context (last 6 turns max)
        var conversationContext = ""
        let recentHistory = chatHistory.suffix(6)
        if recentHistory.count > 0 {
            conversationContext = "\n## Recent Conversation\n"
            for turn in recentHistory {
                if turn.role == "user" {
                    conversationContext += "User: \(turn.content)\n"
                } else if turn.content == "[[DOCUMENT_GENERATED]]" {
                    conversationContext += "Assistant: [Generated the document]\n"
                } else if turn.content == "[[DOCUMENT_UPDATED]]" {
                    conversationContext += "Assistant: [Updated the document]\n"
                } else if turn.role == "assistant" {
                    conversationContext += "Assistant: \(turn.content)\n"
                }
            }
            conversationContext += "\n"
        }

        let userMessage = """
            Here is the current document:

            ---
            \(currentDocument)
            ---
            \(conversationContext)
            Current user request: \(request)

            IMPORTANT: If you need clarification, you MUST start your response with [CONVERSATION].
            If this is an editing request, return the full updated document only.
            """

        do {
            let result = try await aiService.processWithMemory(
                userMessage: userMessage,
                systemPrompt: systemPrompt,
                isRefinement: true  // Don't add conflicting "output only" rules
            )

            let conversationMarker = "[CONVERSATION]"
            if result.hasPrefix(conversationMarker) {
                let cleanedResult = String(result.dropFirst(conversationMarker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                aiOutput = cleanedResult
                chatHistory.append((role: "assistant", content: cleanedResult))
            } else {
                aiOutput = result
                currentDocument = result
                changedLineIndices = computeChangedLines(from: previousDocument, to: result)
                chatHistory.append((role: "assistant", content: "[[DOCUMENT_UPDATED]]"))
            }

            isAIProcessing = false
        } catch {
            if !Task.isCancelled {
                aiError = error.localizedDescription
                isAIProcessing = false
            }
        }
    }

    /// Exit refinement mode
    func exitRefinementMode() {
        isInRefinementMode = false
        aiOutput = ""
        chatHistory = []
        refinementInput = ""
    }

    /// Regenerate AI output
    func regenerateAIOutput() {
        isInRefinementMode = false
        chatHistory = []
        processWithAI()
    }

    /// Start over - reset all AI state
    func startOver() {
        currentAITask?.cancel()
        aiService.cancel()

        isInRefinementMode = false
        aiOutput = ""
        chatHistory = []
        refinementInput = ""
        customInstructions = ""
        aiError = nil
        isAIProcessing = false

        // Reset memory mode state
        isMemoryMode = false
        detectedDocuments.removeAll()
        isDetectingDocuments = false
        memoryModeInitialized = false
        aiService.resetMemoryMode()

        aiService.resetContext()
    }

    /// Cancel ongoing AI request
    func cancelAIRequest() {
        currentAITask?.cancel()
        aiService.cancel()
        isAIProcessing = false
    }

    /// Cancel AI and cleanup state (for back navigation)
    /// Preserves user preferences (sliders, doc type) but clears AI work
    func cancelAndCleanup() {
        // Cancel any running tasks
        currentAITask?.cancel()
        aiService.cancel()

        // Clear AI output and chat
        aiOutput = ""
        chatHistory = []
        aiError = nil
        isAIProcessing = false
        isInRefinementMode = false
        refinementInput = ""

        // Reset document state
        currentDocument = ""
        previousDocument = ""
        changedLineIndices = []

        // Reset memory mode
        isMemoryMode = false
        detectedDocuments.removeAll()
        isDetectingDocuments = false
        memoryModeInitialized = false
        crossDocumentNotes = ""
        aiService.resetMemoryMode()

        // Clear source documents (they'll be re-transferred if user continues again)
        sourceDocuments.removeAll()
        selectedDocumentId = nil

        aiService.resetContext()
    }

    /// Reset all state (for clearAll)
    func clearAll() {
        aiOutput = ""
        aiError = nil
        currentDocument = ""
        previousDocument = ""
        changedLineIndices = []
        chatHistory = []
        isInRefinementMode = false
        refinementInput = ""
        customInstructions = ""
        sliderSettings = SliderSettings()
        isAIProcessing = false
        lastProcessedRedactedText = ""
        aiService.resetContext()

        // Clear multi-document state
        sourceDocuments.removeAll()
        selectedDocumentId = nil

        // Clear memory mode state
        isMemoryMode = false
        detectedDocuments.removeAll()
        isDetectingDocuments = false
        memoryModeInitialized = false
        crossDocumentNotes = ""
        aiService.resetMemoryMode()
    }

    /// Reset memory mode files on app launch (clears stale files from previous session)
    func resetMemoryModeOnLaunch() {
        aiService.resetMemoryMode()
    }

    // MARK: - Sheet Actions

    func editPrompt(for docType: DocumentType) {
        documentTypeToEdit = docType
        showPromptEditor = true
    }

    func openAddCustomCategory() {
        showAddCustomCategory = true
    }

    func dismissError() {
        aiError = nil
    }

    // MARK: - Copy Actions

    func copyCurrentDocument() {
        guard !currentDocument.isEmpty else { return }
        copyFormattedToClipboard(currentDocument)
    }

    private func copyFormattedToClipboard(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtfData = MarkdownParser.parseToRTFData(markdown) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        pasteboard.setString(markdown, forType: .string)
    }

    // MARK: - Private Methods

    private func computeChangedLines(from oldDoc: String, to newDoc: String) -> Set<Int> {
        let oldLines = oldDoc.components(separatedBy: .newlines)
        let newLines = newDoc.components(separatedBy: .newlines)

        var changedIndices = Set<Int>()
        let normalizedOldLines = Set(oldLines.map { normalizeLine($0) })

        for (index, newLine) in newLines.enumerated() {
            let normalizedNew = normalizeLine(newLine)

            if normalizedNew.isEmpty { continue }

            if index >= oldLines.count {
                if !normalizedOldLines.contains(normalizedNew) {
                    changedIndices.insert(index)
                }
            } else {
                let normalizedOld = normalizeLine(oldLines[index])
                if normalizedOld != normalizedNew {
                    if !normalizedOldLines.contains(normalizedNew) {
                        changedIndices.insert(index)
                    }
                }
            }
        }

        return changedIndices
    }

    private func normalizeLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
