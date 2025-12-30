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

    // MARK: - Actions

    /// Process text with AI using selected document type
    func processWithAI() {
        guard let getText = getRedactedText else {
            aiError = "No text provider configured"
            return
        }

        let inputForAI = getText()
        guard !inputForAI.isEmpty else {
            aiError = "No redacted text to process"
            return
        }

        guard let docType = selectedDocumentType else {
            aiError = "No document type selected"
            return
        }

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

        currentAITask = Task {
            do {
                let stream = aiService.processStreaming(text: inputForAI, prompt: fullPrompt)

                for try await chunk in stream {
                    if Task.isCancelled { break }
                    aiOutput += chunk
                }

                currentDocument = aiOutput
                isInRefinementMode = true
                chatHistory.append((role: "assistant", content: aiOutput))
                isAIProcessing = false
            } catch {
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
