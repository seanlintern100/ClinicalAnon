//
//  RedactPhaseState.swift
//  Redactor
//
//  Purpose: Manages state for the Redact phase of the workflow
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Redact Phase State

/// State management for the Redact (anonymization) phase
@MainActor
class RedactPhaseState: ObservableObject {

    // MARK: - Input/Output

    @Published var inputText: String = ""
    @Published var result: AnonymizationResult?

    // MARK: - Processing State

    @Published var isProcessing: Bool = false
    @Published var estimatedSeconds: Int = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - Entity Management

    @Published var excludedEntityIds: Set<UUID> = []
    @Published var customEntities: [Entity] = []

    // Local LLM PII review
    @Published var piiReviewFindings: [Entity] = []
    @Published var isReviewingPII: Bool = false
    @Published var piiReviewError: String?
    private var entitiesToRemove: Set<UUID> = []

    // BERT NER scan
    @Published var bertNERFindings: [Entity] = []
    @Published var isRunningBertNER: Bool = false
    @Published var bertNERError: String?

    // XLM-R NER scan (multilingual)
    @Published var xlmrNERFindings: [Entity] = []
    @Published var isRunningXLMRNER: Bool = false
    @Published var xlmrNERError: String?

    // Private backing store for excluded IDs (pending changes)
    private var _excludedIds: Set<UUID> = []
    @Published var hasPendingChanges: Bool = false

    // MARK: - Cached Text

    @Published private(set) var cachedRedactedText: String = ""
    private var redactedTextNeedsUpdate: Bool = true

    // MARK: - UI State

    @Published var showingAddCustom: Bool = false
    @Published var prefilledText: String? = nil

    // Copy button feedback
    @Published var justCopiedAnonymized: Bool = false
    @Published var justCopiedOriginal: Bool = false
    @Published var hasCopiedRedacted: Bool = false

    // Clipboard auto-clear
    private var clipboardClearTask: DispatchWorkItem?

    // MARK: - Services

    private let engine: AnonymizationEngine
    weak var cacheManager: HighlightCacheManager?

    // MARK: - Initialization

    init(engine: AnonymizationEngine) {
        self.engine = engine
    }

    // MARK: - Computed Properties

    /// All entities (detected + custom + PII review + BERT NER + XLM-R NER findings)
    var allEntities: [Entity] {
        guard let result = result else { return customEntities + piiReviewFindings + bertNERFindings + xlmrNERFindings }
        let baseEntities = result.entities.filter { !entitiesToRemove.contains($0.id) }
        return baseEntities + customEntities + piiReviewFindings + bertNERFindings + xlmrNERFindings
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

    /// Whether Continue button should be enabled
    var canContinue: Bool {
        result != nil && !hasPendingChanges
    }

    // MARK: - Actions

    func analyze() async {
        guard !inputText.isEmpty else { return }

        errorMessage = nil
        successMessage = nil
        hasCopiedRedacted = false

        isProcessing = true
        estimatedSeconds = 0
        statusMessage = "Starting..."

        do {
            let updateTask = Task {
                while isProcessing {
                    updateFromEngine()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            result = try await engine.anonymize(inputText)

            redactedTextNeedsUpdate = true
            _excludedIds = excludedEntityIds

            // Note: Cache rebuild is now handled by WorkflowViewModel.analyze()
            // to ensure strong reference to cacheManager is used

            updateTask.cancel()
            updateFromEngine()

            isProcessing = false
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
        piiReviewFindings.removeAll()
        bertNERFindings.removeAll()
        xlmrNERFindings.removeAll()
        entitiesToRemove.removeAll()
        isReviewingPII = false
        piiReviewError = nil
        isRunningBertNER = false
        bertNERError = nil
        isRunningXLMRNER = false
        xlmrNERError = nil
        engine.clearSession()
        errorMessage = nil
        successMessage = nil

        cachedRedactedText = ""
        redactedTextNeedsUpdate = true

        hasCopiedRedacted = false
        hasPendingChanges = false
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

    /// Toggle all entities in a group - if any are active, exclude all; if all excluded, include all
    func toggleEntities(_ entities: [Entity]) {
        let allExcluded = entities.allSatisfy { _excludedIds.contains($0.id) }

        if allExcluded {
            // Include all
            for entity in entities {
                _excludedIds.remove(entity.id)
            }
        } else {
            // Exclude all
            for entity in entities {
                _excludedIds.insert(entity.id)
            }
        }
        hasPendingChanges = true
    }

    func applyChanges() {
        guard hasPendingChanges else { return }

        excludedEntityIds = _excludedIds
        redactedTextNeedsUpdate = true

        // Note: Cache rebuild is now handled by WorkflowViewModel.applyChanges()

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

        // Note: Cache rebuild is now handled by WorkflowViewModel.addCustomEntity()

        successMessage = "Added custom redaction: \(code) (\(positions.count) occurrences)"
        autoHideSuccess()
    }

    // MARK: - Local LLM PII Review

    func runLocalPIIReview() async {
        guard let result = result else {
            piiReviewError = "Please analyze text first"
            return
        }

        guard LocalLLMService.shared.isAvailable else {
            errorMessage = "Local LLM requires Apple Silicon (M1/M2/M3/M4)."
            return
        }

        isReviewingPII = true
        piiReviewError = nil

        // Show appropriate status message
        if !LocalLLMService.shared.isModelLoaded {
            successMessage = "Loading model..."
        } else {
            successMessage = "Analyzing text (this may take several minutes)..."
        }

        do {
            // Pass original text and existing entities - LLM will find deltas
            let findings = try await LocalLLMService.shared.reviewForMissedPII(
                originalText: result.originalText,
                existingEntities: allEntities,
                onAnalysisStarted: { [weak self] in
                    Task { @MainActor in
                        self?.successMessage = "Analyzing text (this may take several minutes)..."
                    }
                }
            )

            await MainActor.run {
                processPIIFindings(findings, originalText: result.originalText)
                isReviewingPII = false

                if piiReviewFindings.isEmpty && entitiesToRemove.isEmpty {
                    successMessage = "No additional PII detected"
                    autoHideSuccess()
                } else {
                    let newCount = piiReviewFindings.count
                    let mergedCount = entitiesToRemove.count
                    var message = ""
                    if newCount > 0 {
                        message += "Found \(newCount) potential PII item(s)"
                    }
                    if mergedCount > 0 {
                        message += message.isEmpty ? "" : ". "
                        message += "Merged \(mergedCount) partial detection(s)"
                    }
                    successMessage = message
                    autoHideSuccess()
                    redactedTextNeedsUpdate = true

                    // Note: Cache rebuild is now handled by WorkflowViewModel.runLocalPIIReview()
                }
            }
        } catch {
            await MainActor.run {
                isReviewingPII = false
                piiReviewError = error.localizedDescription
                errorMessage = "PII review failed: \(error.localizedDescription)"
            }
        }
    }

    private func processPIIFindings(_ findings: [PIIFinding], originalText: String) {
        var newEntities: [Entity] = []

        print("DEBUG processPIIFindings: Received \(findings.count) findings")
        for finding in findings {
            print("DEBUG processPIIFindings: Processing '\(finding.text)' type=\(finding.suggestedType)")

            if let (matchedEntity, leakedPart) = findPartialMatch(finding.text) {
                let fullOriginal = matchedEntity.originalText + leakedPart
                let positions = findAllOccurrences(of: fullOriginal, in: originalText)

                if !positions.isEmpty {
                    let replacement = Entity(
                        originalText: fullOriginal,
                        replacementCode: matchedEntity.replacementCode,
                        type: matchedEntity.type,
                        positions: positions,
                        confidence: finding.confidence
                    )

                    entitiesToRemove.insert(matchedEntity.id)
                    newEntities.append(replacement)
                }
            } else {
                let alreadyExists = allEntities.contains { $0.originalText.lowercased() == finding.text.lowercased() }
                if alreadyExists {
                    print("DEBUG processPIIFindings: '\(finding.text)' already exists, skipping")
                    continue
                }

                let positions = findAllOccurrences(of: finding.text, in: originalText)
                if positions.isEmpty {
                    print("DEBUG processPIIFindings: '\(finding.text)' not found in original text, skipping")
                    continue
                }
                print("DEBUG processPIIFindings: '\(finding.text)' found at \(positions.count) positions, adding")

                let existingCount = allEntities.filter { $0.type == finding.suggestedType }.count + newEntities.filter { $0.type == finding.suggestedType }.count
                let code = finding.suggestedType.replacementCode(for: existingCount)

                let entity = Entity(
                    originalText: finding.text,
                    replacementCode: code,
                    type: finding.suggestedType,
                    positions: positions,
                    confidence: finding.confidence
                )

                newEntities.append(entity)
            }
        }

        // Merge with existing findings, avoiding duplicates
        let existingPIITexts = Set(piiReviewFindings.map { $0.originalText.lowercased() })
        let uniqueNewEntities = newEntities.filter { !existingPIITexts.contains($0.originalText.lowercased()) }
        piiReviewFindings.append(contentsOf: uniqueNewEntities)
    }

    private func findPartialMatch(_ findingText: String) -> (Entity, String)? {
        for entity in allEntities {
            if findingText.contains(entity.replacementCode) {
                let leaked = findingText.replacingOccurrences(of: entity.replacementCode, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !leaked.isEmpty {
                    return (entity, leaked)
                }
            }
        }
        return nil
    }

    // MARK: - BERT NER Scan

    /// Run BERT-based NER scan using CoreML model
    func runBertNERScan() async {
        guard let result = result else {
            bertNERError = "Please analyze text first"
            return
        }

        guard BertNERService.shared.isAvailable else {
            errorMessage = "BERT NER not available on this device."
            return
        }

        isRunningBertNER = true
        bertNERError = nil

        // Show appropriate status message
        if !BertNERService.shared.isModelLoaded {
            successMessage = "Loading BERT model..."
        } else {
            successMessage = "Running BERT NER scan..."
        }

        do {
            let findings = try await BertNERService.shared.runNERScan(
                text: result.originalText,
                existingEntities: allEntities
            )

            await MainActor.run {
                processBertNERFindings(findings, originalText: result.originalText)
                isRunningBertNER = false

                if bertNERFindings.isEmpty {
                    successMessage = "BERT scan complete - no additional entities found"
                } else {
                    successMessage = "BERT scan found \(bertNERFindings.count) additional entity/entities"
                }
                autoHideSuccess()
                redactedTextNeedsUpdate = true
            }
        } catch {
            await MainActor.run {
                isRunningBertNER = false
                bertNERError = error.localizedDescription
                errorMessage = "BERT NER scan failed: \(error.localizedDescription)"
            }
        }
    }

    private func processBertNERFindings(_ findings: [PIIFinding], originalText: String) {
        var newEntities: [Entity] = []

        for finding in findings {
            // Skip if text already exists in current entities
            let alreadyExists = allEntities.contains { $0.originalText.lowercased() == finding.text.lowercased() }
            if alreadyExists { continue }

            // Skip if already added in this batch
            if newEntities.contains(where: { $0.originalText.lowercased() == finding.text.lowercased() }) {
                continue
            }

            // Find all occurrences in original text
            let positions = findAllOccurrences(of: finding.text, in: originalText)
            guard !positions.isEmpty else { continue }

            // Get next available replacement code
            let existingCount = allEntities.filter { $0.type == finding.suggestedType }.count +
                               newEntities.filter { $0.type == finding.suggestedType }.count
            let code = finding.suggestedType.replacementCode(for: existingCount)

            let entity = Entity(
                originalText: finding.text,
                replacementCode: code,
                type: finding.suggestedType,
                positions: positions,
                confidence: finding.confidence
            )

            newEntities.append(entity)
        }

        // Merge with existing BERT findings, avoiding duplicates
        let existingBertTexts = Set(bertNERFindings.map { $0.originalText.lowercased() })
        let uniqueNewEntities = newEntities.filter { !existingBertTexts.contains($0.originalText.lowercased()) }
        bertNERFindings.append(contentsOf: uniqueNewEntities)
    }

    // MARK: - XLM-R NER Scan (Multilingual)

    /// Run XLM-RoBERTa NER scan for multilingual name detection
    func runXLMRNERScan() async {
        guard let result = result else {
            xlmrNERError = "Please analyze text first"
            return
        }

        guard XLMRobertaNERService.shared.isAvailable else {
            errorMessage = "XLM-R NER not available on this device."
            return
        }

        isRunningXLMRNER = true
        xlmrNERError = nil

        // Show appropriate status message
        if !XLMRobertaNERService.shared.isModelLoaded {
            successMessage = "Loading XLM-R model..."
        } else {
            successMessage = "Running XLM-R NER scan..."
        }

        do {
            let findings = try await XLMRobertaNERService.shared.runNERScan(
                text: result.originalText,
                existingEntities: allEntities
            )

            await MainActor.run {
                processXLMRNERFindings(findings, originalText: result.originalText)
                isRunningXLMRNER = false

                if xlmrNERFindings.isEmpty {
                    successMessage = "XLM-R scan complete - no additional entities found"
                } else {
                    successMessage = "XLM-R scan found \(xlmrNERFindings.count) additional entity/entities"
                }
                autoHideSuccess()
                redactedTextNeedsUpdate = true
            }
        } catch {
            await MainActor.run {
                isRunningXLMRNER = false
                xlmrNERError = error.localizedDescription
                errorMessage = "XLM-R NER scan failed: \(error.localizedDescription)"
            }
        }
    }

    private func processXLMRNERFindings(_ findings: [PIIFinding], originalText: String) {
        var newEntities: [Entity] = []

        for finding in findings {
            // Skip if text already exists in current entities
            let alreadyExists = allEntities.contains { $0.originalText.lowercased() == finding.text.lowercased() }
            if alreadyExists { continue }

            // Skip if already added in this batch
            if newEntities.contains(where: { $0.originalText.lowercased() == finding.text.lowercased() }) {
                continue
            }

            // Find all occurrences in original text
            let positions = findAllOccurrences(of: finding.text, in: originalText)
            guard !positions.isEmpty else { continue }

            // Get next available replacement code
            let existingCount = allEntities.filter { $0.type == finding.suggestedType }.count +
                               newEntities.filter { $0.type == finding.suggestedType }.count
            let code = finding.suggestedType.replacementCode(for: existingCount)

            let entity = Entity(
                originalText: finding.text,
                replacementCode: code,
                type: finding.suggestedType,
                positions: positions,
                confidence: finding.confidence
            )

            newEntities.append(entity)
        }

        // Merge with existing XLM-R findings, avoiding duplicates
        let existingXLMRTexts = Set(xlmrNERFindings.map { $0.originalText.lowercased() })
        let uniqueNewEntities = newEntities.filter { !existingXLMRTexts.contains($0.originalText.lowercased()) }
        xlmrNERFindings.append(contentsOf: uniqueNewEntities)
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

    func dismissError() {
        errorMessage = nil
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

        // Sort by start position (ascending) to detect overlaps
        allReplacements.sort { $0.start < $1.start }

        // Remove overlapping positions, keeping the longer replacement
        var nonOverlapping: [(start: Int, end: Int, code: String)] = []
        for replacement in allReplacements {
            if let last = nonOverlapping.last {
                // Check if this replacement overlaps with the previous one
                if replacement.start < last.end {
                    // Overlapping - keep the longer one
                    let lastLength = last.end - last.start
                    let currentLength = replacement.end - replacement.start
                    if currentLength > lastLength {
                        // Current is longer, replace the last one
                        nonOverlapping.removeLast()
                        nonOverlapping.append(replacement)
                    }
                    // Otherwise keep the existing (last) one
                } else {
                    // No overlap, add it
                    nonOverlapping.append(replacement)
                }
            } else {
                // First replacement
                nonOverlapping.append(replacement)
            }
        }

        // Sort in descending order for replacement (process end-to-start)
        nonOverlapping.sort { $0.start > $1.start }

        for replacement in nonOverlapping {
            guard replacement.start < text.count && replacement.end <= text.count else { continue }

            let start = text.index(text.startIndex, offsetBy: replacement.start)
            let end = text.index(text.startIndex, offsetBy: replacement.end)

            guard start < text.endIndex && end <= text.endIndex && start < end else { continue }
            text.replaceSubrange(start..<end, with: replacement.code)
        }

        cachedRedactedText = text
        redactedTextNeedsUpdate = false
    }

    private func findAllOccurrences(of searchText: String, in text: String) -> [[Int]] {
        // Normalize apostrophes for matching (curly ' and straight ')
        let normalizedSearch = searchText
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")
        let normalizedText = text
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")

        var positions: [[Int]] = []
        var searchStartIndex = normalizedText.startIndex

        while searchStartIndex < normalizedText.endIndex {
            if let range = normalizedText.range(of: normalizedSearch, options: .caseInsensitive, range: searchStartIndex..<normalizedText.endIndex) {
                let start = normalizedText.distance(from: normalizedText.startIndex, to: range.lowerBound)
                let end = normalizedText.distance(from: normalizedText.startIndex, to: range.upperBound)
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

    private func scheduleClipboardClear() {
        clipboardClearTask?.cancel()
        clipboardClearTask = DispatchWorkItem { [weak self] in
            NSPasteboard.general.clearContents()
            self?.clipboardClearTask = nil
        }
        if let task = clipboardClearTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: task)
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

    /// Force cache invalidation (called when entities change externally)
    func invalidateCache() {
        redactedTextNeedsUpdate = true
    }
}
