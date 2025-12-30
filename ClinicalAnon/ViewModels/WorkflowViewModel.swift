//
//  WorkflowViewModel.swift
//  Redactor
//
//  Purpose: Manages state for the staged anonymization workflow
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

// MARK: - Workflow ViewModel

/// Main view model for the three-phase anonymization workflow
@MainActor
class WorkflowViewModel: ObservableObject {

    // MARK: - Workflow Phase

    @Published var currentPhase: WorkflowPhase = .redact

    // MARK: - Redact Phase Properties

    @Published var inputText: String = ""
    @Published var result: AnonymizationResult?
    @Published var isProcessing: Bool = false
    @Published var estimatedSeconds: Int = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // Entity management
    @Published var excludedEntityIds: Set<UUID> = []
    @Published var customEntities: [Entity] = []

    // Performance: Cached redacted text
    @Published private(set) var cachedRedactedText: String = ""
    private var redactedTextNeedsUpdate: Bool = true

    // Performance: Cached AttributedStrings
    @Published private(set) var cachedOriginalAttributed: AttributedString?
    @Published private(set) var cachedRedactedAttributed: AttributedString?
    @Published private(set) var cachedRestoredAttributed: AttributedString?

    // Private backing store for excluded IDs
    private var _excludedIds: Set<UUID> = []

    // Add custom entity dialog state
    @Published var showingAddCustom: Bool = false
    @Published var prefilledText: String? = nil

    // Copy button feedback
    @Published var justCopiedAnonymized: Bool = false
    @Published var justCopiedOriginal: Bool = false
    @Published var justCopiedRestored: Bool = false

    // Clipboard auto-clear (security)
    private var clipboardClearTask: DispatchWorkItem?

    // Completion state for card color changes
    @Published var hasCopiedRedacted: Bool = false
    @Published var hasRestoredText: Bool = false

    // Entity toggle pending changes
    @Published var hasPendingChanges: Bool = false

    // MARK: - Improve Phase Properties

    @Published var selectedDocumentType: DocumentType? = DocumentType.notes
    @Published var sliderSettings: SliderSettings = SliderSettings()  // Current slider values
    @Published var customInstructions: String = ""  // For Custom type only
    @Published var aiOutput: String = ""
    @Published var isAIProcessing: Bool = false
    @Published var aiError: String?

    // Refinement mode - after first generation
    @Published var isInRefinementMode: Bool = false
    @Published var refinementInput: String = ""  // User's refinement request
    @Published var chatHistory: [(role: String, content: String)] = []  // Chat history for display
    @Published var streamingDestination: StreamingDestination = .unknown  // Where current stream goes

    // Track what redacted text was used for AI generation
    private var lastProcessedRedactedText: String = ""

    // The actual document (left pane) - separate from chat responses
    @Published var currentDocument: String = ""

    // Track previous output for highlighting changes
    @Published var previousDocument: String = ""
    @Published var changedLineIndices: Set<Int> = []  // Lines that changed in last update

    // Sheet states for editing/adding document types
    @Published var showPromptEditor: Bool = false
    @Published var showAddCustomCategory: Bool = false
    @Published var documentTypeToEdit: DocumentType?

    // Conversation context is now managed by AIAssistantService
    // Access via aiService.context for message history

    // MARK: - Restore Phase Properties

    @Published var finalRestoredText: String = ""

    // MARK: - Services

    let engine: AnonymizationEngine
    let aiService: AIAssistantService

    // AI task for cancellation
    private var currentAITask: Task<Void, Never>?

    // MARK: - Initialization

    init(engine: AnonymizationEngine, aiService: AIAssistantService) {
        self.engine = engine
        self.aiService = aiService
    }

    convenience init() {
        let engine = AnonymizationEngine()
        let bedrockService = BedrockService()
        let credentialsManager = AWSCredentialsManager.shared
        let aiService = AIAssistantService(bedrockService: bedrockService, credentialsManager: credentialsManager)
        self.init(engine: engine, aiService: aiService)

        // Auto-configure BedrockService with built-in credentials
        Task {
            if let credentials = credentialsManager.loadCredentials() {
                try? await bedrockService.configure(with: credentials)
            }
        }
    }

    // MARK: - Computed Properties

    /// All entities (detected + custom)
    var allEntities: [Entity] {
        guard let result = result else { return customEntities }
        return result.entities + customEntities
    }

    /// Only active entities (not excluded)
    var activeEntities: [Entity] {
        allEntities.filter { !_excludedIds.contains($0.id) }
    }

    /// Check if an entity is excluded
    func isEntityExcluded(_ entity: Entity) -> Bool {
        _excludedIds.contains(entity.id)
    }

    /// Dynamically generated redacted text based on active entities
    var displayedRedactedText: String {
        if redactedTextNeedsUpdate {
            updateRedactedTextCache()
        }
        return cachedRedactedText
    }

    /// Whether Continue button should be enabled in Redact phase
    var canContinueFromRedact: Bool {
        result != nil && !hasPendingChanges
    }

    /// Whether Continue button should be enabled in Improve phase
    var canContinueFromImprove: Bool {
        !aiOutput.isEmpty && !isAIProcessing
    }

    /// Whether AI has generated output (for UI state)
    var hasGeneratedOutput: Bool {
        !chatHistory.isEmpty || (!aiOutput.isEmpty && !isAIProcessing)
    }

    /// Whether the redacted input has changed since AI generation
    var inputChangedSinceGeneration: Bool {
        hasGeneratedOutput && lastProcessedRedactedText != displayedRedactedText
    }

    // MARK: - Phase Navigation

    func goToPhase(_ phase: WorkflowPhase) {
        currentPhase = phase
    }

    func goToNextPhase() {
        if let next = currentPhase.next {
            currentPhase = next
        }
    }

    func goToPreviousPhase() {
        if let previous = currentPhase.previous {
            currentPhase = previous
        }
    }

    /// Continue from current phase (with validation)
    func continueToNextPhase() {
        switch currentPhase {
        case .redact:
            guard canContinueFromRedact else { return }
            currentPhase = .improve
        case .improve:
            guard canContinueFromImprove else { return }
            // Automatically restore names when moving to restore phase
            restoreNamesFromAIOutput()
            currentPhase = .restore
        case .restore:
            break // Already at final phase
        }
    }

    // MARK: - Redact Phase Actions

    func analyze() async {
        guard !inputText.isEmpty else { return }

        // Dismiss previous messages
        errorMessage = nil
        successMessage = nil

        // Reset completion states for new analysis
        hasCopiedRedacted = false
        hasRestoredText = false

        // Reset AI output when re-analyzing
        aiOutput = ""
        finalRestoredText = ""

        // Set initial state
        isProcessing = true
        estimatedSeconds = 0
        statusMessage = "Starting..."

        do {
            // Poll for updates during processing
            let updateTask = Task {
                while isProcessing {
                    updateFromEngine()
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }

            result = try await engine.anonymize(inputText)

            // Invalidate cache so it rebuilds with new entities
            redactedTextNeedsUpdate = true

            // Sync backing store from published (fresh start after analyze)
            _excludedIds = excludedEntityIds

            // Build highlighted AttributedString caches
            rebuildAllHighlightCaches()

            updateTask.cancel()
            updateFromEngine()

            successMessage = "Anonymization complete! Found \(result?.entityCount ?? 0) entities."
            autoHideSuccess()
        } catch {
            isProcessing = false
            estimatedSeconds = 0
            statusMessage = ""

            if let appError = error as? AppError {
                errorMessage = appError.errorDescription ?? "An error occurred"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearAll() {
        inputText = ""
        result = nil
        excludedEntityIds.removeAll()
        _excludedIds.removeAll()
        customEntities.removeAll()
        engine.clearSession()
        errorMessage = nil
        successMessage = nil

        // Reset caches
        cachedRedactedText = ""
        redactedTextNeedsUpdate = true
        cachedOriginalAttributed = nil
        cachedRedactedAttributed = nil
        cachedRestoredAttributed = nil

        // Reset completion states
        hasCopiedRedacted = false
        hasRestoredText = false
        hasPendingChanges = false

        // Reset AI state
        aiOutput = ""
        aiError = nil
        finalRestoredText = ""
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

        // Reset conversation context for new session
        aiService.resetContext()

        // Go back to redact phase
        currentPhase = .redact
    }

    // MARK: - Entity Management

    func toggleEntity(_ entity: Entity) {
        if _excludedIds.contains(entity.id) {
            _excludedIds.remove(entity.id)
        } else {
            _excludedIds.insert(entity.id)
        }
        hasPendingChanges = true
    }

    func applyChanges() {
        guard hasPendingChanges else { return }

        excludedEntityIds = _excludedIds
        redactedTextNeedsUpdate = true
        rebuildAllHighlightCaches()
        hasPendingChanges = false
    }

    func openAddCustomEntity(withText text: String? = nil) {
        prefilledText = text
        showingAddCustom = true
    }

    func addCustomEntity(text: String, type: EntityType) {
        guard let result = result else {
            errorMessage = "Please analyze text first"
            return
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            errorMessage = "Please enter text to redact"
            return
        }

        let positions = findAllOccurrences(of: trimmedText, in: result.originalText)
        guard !positions.isEmpty else {
            errorMessage = "Text '\(trimmedText)' not found in original document"
            return
        }

        let existingCount = allEntities.filter { $0.type == type }.count
        let code = type.replacementCode(for: existingCount)

        let entity = Entity(
            originalText: trimmedText,
            replacementCode: code,
            type: type,
            positions: positions,
            confidence: 1.0
        )

        customEntities.append(entity)
        _ = engine.entityMapping.getReplacementCode(for: trimmedText, type: type)
        redactedTextNeedsUpdate = true
        rebuildAllHighlightCaches()

        successMessage = "Added custom redaction: \(code) (\(positions.count) occurrences)"
        autoHideSuccess()
    }

    // MARK: - Improve Phase Actions

    /// Process text with AI using selected document type
    func processWithAI() {
        let inputForAI = displayedRedactedText
        guard !inputForAI.isEmpty else {
            aiError = "No redacted text to process"
            return
        }

        guard let docType = selectedDocumentType else {
            aiError = "No document type selected"
            return
        }

        // Cancel any existing AI task
        currentAITask?.cancel()
        aiService.cancel()

        // Clear previous output and chat history
        aiOutput = ""
        aiError = nil
        isAIProcessing = true
        chatHistory = []

        // Track what input we're processing and clear change tracking
        lastProcessedRedactedText = inputForAI
        previousDocument = ""
        changedLineIndices = []
        currentDocument = ""

        // Build prompt with slider settings injected
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

                // Initial generation is always a document
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
        guard !request.isEmpty else {
            #if DEBUG
            print("⚠️ [Refinement] Empty request, skipping")
            #endif
            return
        }
        guard !aiOutput.isEmpty else {
            #if DEBUG
            print("⚠️ [Refinement] No AI output to refine, skipping")
            #endif
            return
        }

        #if DEBUG
        print("📝 [Refinement] Starting refinement with request: \(request.prefix(50))...")
        #endif

        // Add user message to chat history
        chatHistory.append((role: "user", content: request))
        refinementInput = ""

        // Cancel any existing AI task
        currentAITask?.cancel()
        aiService.cancel()

        aiError = nil
        isAIProcessing = true

        // Store current document for diff highlighting
        previousDocument = currentDocument
        changedLineIndices = []  // Clear previous highlights

        // Build the user message for refinement (includes current doc + request)
        let docSnapshot = currentDocument  // Capture before async
        let userMessage = """
            Here is the current document:

            ---
            \(docSnapshot)
            ---

            User request: \(request)

            If this is an editing request, return the full updated document only.
            If this is a question or discussion, respond conversationally.
            """

        // System prompt for chat (allows both conversation and edits)
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

        #if DEBUG
        print("📤 [Refinement] Sending to AI...")
        #endif

        // Reset streaming destination
        streamingDestination = .unknown

        currentAITask = Task {
            do {
                // Clear output for new version
                aiOutput = ""
                let conversationMarker = "[CONVERSATION]"

                let stream = aiService.processStreaming(text: userMessage, prompt: systemPrompt)

                var chunkCount = 0
                for try await chunk in stream {
                    if Task.isCancelled {
                        #if DEBUG
                        print("⚠️ [Refinement] Task cancelled")
                        #endif
                        break
                    }
                    chunkCount += 1
                    aiOutput += chunk

                    // Detect destination from accumulated output (marker might span chunks)
                    if streamingDestination == .unknown && aiOutput.count >= conversationMarker.count {
                        if aiOutput.hasPrefix(conversationMarker) {
                            streamingDestination = .chat
                            // Strip the marker from output
                            aiOutput = String(aiOutput.dropFirst(conversationMarker.count))
                            // Also strip leading whitespace/newlines after marker
                            aiOutput = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                            #if DEBUG
                            print("💬 [Refinement] Detected CONVERSATION response")
                            #endif
                        } else {
                            streamingDestination = .document
                            #if DEBUG
                            print("📄 [Refinement] Detected DOCUMENT response")
                            #endif
                        }
                    }

                    #if DEBUG
                    if chunkCount == 1 {
                        print("📥 [Refinement] First chunk received")
                    }
                    #endif
                }

                #if DEBUG
                print("✅ [Refinement] Complete - received \(chunkCount) chunks, output length: \(aiOutput.count)")
                #endif

                // Handle completion based on detected destination
                if streamingDestination == .document {
                    // Update the document and compute diff
                    currentDocument = aiOutput
                    changedLineIndices = self.computeChangedLines(from: previousDocument, to: aiOutput)
                    chatHistory.append((role: "assistant", content: "[[DOCUMENT_UPDATED]]"))
                    #if DEBUG
                    print("📄 [Refinement] Document updated, \(changedLineIndices.count) lines changed")
                    #endif
                } else {
                    // Conversational - add to chat history
                    chatHistory.append((role: "assistant", content: aiOutput))
                    #if DEBUG
                    print("💬 [Refinement] Chat response added to history")
                    #endif
                }

                streamingDestination = .unknown
                isAIProcessing = false
            } catch {
                #if DEBUG
                print("❌ [Refinement] Error: \(error.localizedDescription)")
                #endif
                if !Task.isCancelled {
                    aiError = error.localizedDescription
                    isAIProcessing = false
                }
            }
        }
    }

    /// Exit refinement mode and go back to initial state
    func exitRefinementMode() {
        isInRefinementMode = false
        aiOutput = ""
        chatHistory = []
        refinementInput = ""
    }

    /// Regenerate AI output (redo button)
    func regenerateAIOutput() {
        isInRefinementMode = false
        chatHistory = []
        processWithAI()
    }

    /// Start over - reset all AI state
    func startOverAI() {
        // Cancel any ongoing request
        currentAITask?.cancel()
        aiService.cancel()

        // Reset all AI state
        isInRefinementMode = false
        aiOutput = ""
        chatHistory = []
        refinementInput = ""
        customInstructions = ""
        aiError = nil
        isAIProcessing = false

        // Reset conversation context
        aiService.resetContext()
    }

    /// Cancel ongoing AI request
    func cancelAIRequest() {
        currentAITask?.cancel()
        aiService.cancel()
        isAIProcessing = false
    }

    /// Open prompt editor for a document type
    func editPrompt(for docType: DocumentType) {
        documentTypeToEdit = docType
        showPromptEditor = true
    }

    /// Open add custom category sheet
    func openAddCustomCategory() {
        showAddCustomCategory = true
    }

    // MARK: - Restore Phase Actions

    /// Restore names from AI output
    func restoreNamesFromAIOutput() {
        guard !aiOutput.isEmpty else {
            aiError = "No AI output to restore"
            return
        }

        guard result != nil else {
            aiError = "No entity mapping available"
            return
        }

        let reidentifier = TextReidentifier()
        finalRestoredText = reidentifier.restore(text: aiOutput, using: engine.entityMapping)
        hasRestoredText = true

        // Rebuild restored cache
        cachedRestoredAttributed = buildRestoredAttributed()
    }

    // MARK: - Copy Actions

    func copyInputText() {
        copyToClipboard(inputText)
        justCopiedOriginal = true
        autoResetCopyState { self.justCopiedOriginal = false }
    }

    func copyAnonymizedText() {
        guard result != nil else { return }
        copyToClipboard(displayedRedactedText)
        justCopiedAnonymized = true
        hasCopiedRedacted = true
        autoResetCopyState { self.justCopiedAnonymized = false }
    }

    func copyRestoredText() {
        guard !finalRestoredText.isEmpty else { return }
        copyFormattedToClipboard(finalRestoredText)
        justCopiedRestored = true
        autoResetCopyState { self.justCopiedRestored = false }
    }

    /// Copy the current document to clipboard (used by ImprovePhaseView)
    /// Uses formatted copy to preserve markdown heading formatting
    func copyCurrentDocument() {
        guard !currentDocument.isEmpty else { return }
        copyFormattedToClipboard(currentDocument)
    }

    func dismissError() {
        errorMessage = nil
        aiError = nil
    }

    func dismissSuccess() {
        successMessage = nil
    }

    // MARK: - Private Methods

    private func updateFromEngine() {
        isProcessing = engine.isProcessing
        estimatedSeconds = engine.estimatedSeconds
        statusMessage = engine.statusMessage
    }

    private func updateRedactedTextCache() {
        guard let result = result else {
            cachedRedactedText = ""
            redactedTextNeedsUpdate = false
            return
        }

        var text = result.originalText
        var allReplacements: [(start: Int, end: Int, code: String)] = []

        for entity in activeEntities {
            for position in entity.positions {
                guard position.count >= 2 else { continue }
                let start = position[0]
                let end = position[1]

                guard start >= 0 && end <= text.count && start < end else { continue }
                allReplacements.append((start: start, end: end, code: entity.replacementCode))
            }
        }

        allReplacements.sort { $0.start > $1.start }

        for replacement in allReplacements {
            guard replacement.start < text.count && replacement.end <= text.count else { continue }

            let start = text.index(text.startIndex, offsetBy: replacement.start)
            let end = text.index(text.startIndex, offsetBy: replacement.end)

            guard start < text.endIndex && end <= text.endIndex && start < end else { continue }
            text.replaceSubrange(start..<end, with: replacement.code)
        }

        cachedRedactedText = text
        redactedTextNeedsUpdate = false
    }

    func rebuildAllHighlightCaches() {
        guard let result = result else {
            cachedOriginalAttributed = nil
            cachedRedactedAttributed = nil
            cachedRestoredAttributed = nil
            return
        }

        cachedOriginalAttributed = buildOriginalAttributed(result.originalText)
        cachedRedactedAttributed = buildRedactedAttributed()
        if !finalRestoredText.isEmpty {
            cachedRestoredAttributed = buildRestoredAttributed()
        }
    }

    private func buildOriginalAttributed(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        for entity in allEntities {
            let isExcluded = _excludedIds.contains(entity.id)
            let bgColor = isExcluded
                ? NSColor.gray.withAlphaComponent(0.3)
                : NSColor(entity.type.highlightColor)
            let fgColor = isExcluded
                ? NSColor(DesignSystem.Colors.textSecondary)
                : NSColor(DesignSystem.Colors.textPrimary)

            for position in entity.positions {
                guard position.count >= 2 else { continue }
                let start = position[0]
                let end = position[1]

                guard start >= 0 && end <= text.count && start < end else { continue }

                let startIdx = attributedString.index(attributedString.startIndex, offsetByCharacters: start)
                let endIdx = attributedString.index(attributedString.startIndex, offsetByCharacters: end)

                guard startIdx < attributedString.endIndex && endIdx <= attributedString.endIndex else { continue }

                attributedString[startIdx..<endIdx].backgroundColor = bgColor
                attributedString[startIdx..<endIdx].foregroundColor = fgColor
            }
        }

        return attributedString
    }

    private func buildRedactedAttributed() -> AttributedString {
        let text = displayedRedactedText
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        for entity in activeEntities {
            let code = entity.replacementCode
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex
                if let range = attributedString[searchRange].range(of: code) {
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return attributedString
    }

    private func buildRestoredAttributed() -> AttributedString {
        guard result != nil else { return AttributedString("") }

        var attributedString = MarkdownParser.parseToAttributedString(finalRestoredText, baseFont: .systemFont(ofSize: 14))
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        for entity in allEntities {
            let originalText = entity.originalText
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex
                if let range = attributedString[searchRange].range(of: originalText, options: [.caseInsensitive]) {
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return attributedString
    }

    private func findAllOccurrences(of searchText: String, in text: String) -> [[Int]] {
        var positions: [[Int]] = []
        var searchStartIndex = text.startIndex

        while searchStartIndex < text.endIndex {
            if let range = text.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)
                positions.append([start, end])
                searchStartIndex = range.upperBound
            } else {
                break
            }
        }

        return positions
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        scheduleClipboardClear()
    }

    private func copyFormattedToClipboard(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtfData = MarkdownParser.parseToRTFData(markdown) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        pasteboard.setString(markdown, forType: .string)
        scheduleClipboardClear()
    }

    /// Schedule clipboard to be cleared after 5 minutes for security
    private func scheduleClipboardClear() {
        clipboardClearTask?.cancel()
        clipboardClearTask = DispatchWorkItem { [weak self] in
            NSPasteboard.general.clearContents()
            self?.clipboardClearTask = nil
        }
        if let task = clipboardClearTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: task)  // 5 minutes
        }
    }

    private func autoHideSuccess() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        }
    }

    private func autoResetCopyState(_ reset: @escaping () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            reset()
        }
    }

    // MARK: - Document Diff Helpers

    /// Compute which lines changed between old and new document
    /// Uses normalized comparison to avoid false positives from whitespace differences
    private func computeChangedLines(from oldDoc: String, to newDoc: String) -> Set<Int> {
        let oldLines = oldDoc.components(separatedBy: .newlines)
        let newLines = newDoc.components(separatedBy: .newlines)

        var changedIndices = Set<Int>()

        // Build a set of normalized old lines for quick lookup
        // This helps detect lines that moved vs lines that actually changed
        let normalizedOldLines = Set(oldLines.map { normalizeLine($0) })

        for (index, newLine) in newLines.enumerated() {
            let normalizedNew = normalizeLine(newLine)

            // Skip empty lines - don't highlight blank line differences
            if normalizedNew.isEmpty {
                continue
            }

            if index >= oldLines.count {
                // New line added - but only if content is genuinely new
                if !normalizedOldLines.contains(normalizedNew) {
                    changedIndices.insert(index)
                }
            } else {
                let normalizedOld = normalizeLine(oldLines[index])
                // Line changed - compare normalized versions
                if normalizedOld != normalizedNew {
                    // Only mark as changed if the content didn't exist elsewhere in old doc
                    // (handles reordering without marking everything as changed)
                    if !normalizedOldLines.contains(normalizedNew) {
                        changedIndices.insert(index)
                    }
                }
            }
        }

        return changedIndices
    }

    /// Normalize a line for comparison - trims whitespace and reduces multiple spaces
    private func normalizeLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
