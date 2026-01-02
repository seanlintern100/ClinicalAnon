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

    // MARK: - Sheet States

    @Published var showPromptEditor: Bool = false
    @Published var showAddCustomCategory: Bool = false
    @Published var documentTypeToEdit: DocumentType?

    // MARK: - Services

    private let aiService: AIAssistantService
    private var currentAITask: Task<Void, Never>?

    // Callback to get current redacted text
    var getRedactedText: (() -> String)?

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

    /// Process text with AI using selected document type
    func processWithAI() {
        #if DEBUG
        print("🤖 processWithAI called")
        #endif

        guard let getText = getRedactedText else {
            #if DEBUG
            print("🔴 processWithAI: getRedactedText callback is nil")
            #endif
            aiError = "No text provider configured"
            return
        }

        let inputForAI = getText()
        guard !inputForAI.isEmpty else {
            #if DEBUG
            print("🔴 processWithAI: inputForAI is empty")
            #endif
            aiError = "No redacted text to process"
            return
        }

        guard let docType = selectedDocumentType else {
            #if DEBUG
            print("🔴 processWithAI: selectedDocumentType is nil")
            #endif
            aiError = "No document type selected"
            return
        }

        #if DEBUG
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

        lastProcessedRedactedText = inputForAI
        previousDocument = ""
        changedLineIndices = []
        currentDocument = ""

        var docTypeWithInstructions = docType
        docTypeWithInstructions.customInstructions = customInstructions
        let fullPrompt = docTypeWithInstructions.buildPrompt(with: sliderSettings)

        #if DEBUG
        print("   Prompt length: \(fullPrompt.count) chars")
        print("   Prompt preview: \(String(fullPrompt.prefix(200)))...")
        #endif

        currentAITask = Task {
            do {
                #if DEBUG
                print("🤖 AI Processing: Starting stream...")
                #endif

                let stream = aiService.processStreaming(text: inputForAI, prompt: fullPrompt)

                var chunkCount = 0
                for try await chunk in stream {
                    if Task.isCancelled {
                        #if DEBUG
                        print("🤖 AI Processing: Cancelled after \(chunkCount) chunks")
                        #endif
                        break
                    }
                    aiOutput += chunk
                    chunkCount += 1
                }

                #if DEBUG
                print("🤖 AI Processing: Stream complete - \(chunkCount) chunks, \(aiOutput.count) chars")
                #endif

                currentDocument = aiOutput
                isInRefinementMode = true
                chatHistory.append((role: "assistant", content: aiOutput))
                isAIProcessing = false
            } catch {
                #if DEBUG
                print("🤖 AI Processing: ERROR - \(error.localizedDescription)")
                #endif
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                    isAIProcessing = false
                }
            }
        }
    }

    /// Send refinement request to improve the current output
    func sendRefinement() {
        let request = refinementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        guard !aiOutput.isEmpty else { return }

        chatHistory.append((role: "user", content: request))
        refinementInput = ""

        currentAITask?.cancel()
        aiService.cancel()

        aiError = nil
        isAIProcessing = true

        previousDocument = currentDocument
        changedLineIndices = []

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

            CRITICAL RESPONSE FORMAT:
            - If responding conversationally (answering questions, giving suggestions, discussing),
              start your response with exactly: [CONVERSATION]
            - If providing an updated document, return ONLY the document text with no prefix.

            Examples:
            - User asks "what are the risks?" → Start with [CONVERSATION] then give your answer
            - User asks "make it shorter" → Return the shortened document directly (no prefix)
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

        aiService.resetContext()
    }

    /// Cancel ongoing AI request
    func cancelAIRequest() {
        currentAITask?.cancel()
        aiService.cancel()
        isAIProcessing = false
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
