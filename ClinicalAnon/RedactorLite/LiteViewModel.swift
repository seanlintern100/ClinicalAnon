//
//  LiteViewModel.swift
//  Redactor Lite
//
//  Purpose: Coordinates redaction and restore for the simplified 3-panel workflow.
//           Wraps RedactPhaseState for all engine improvements.
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit
import Combine

// MARK: - Lite View Model

@MainActor
class LiteViewModel: ObservableObject {

    // MARK: - Engine & State

    let engine: AnonymizationEngine
    var redactState: RedactPhaseState
    let cacheManager: HighlightCacheManager
    private let reidentifier = TextReidentifier()
    private var cancellable: AnyCancellable?

    // MARK: - Paste-Back & Restore

    @Published var pastedText: String = ""
    @Published var restoredText: String = ""

    // MARK: - Copy Feedback

    @Published var justCopiedRedacted: Bool = false
    @Published var justCopiedRestored: Bool = false

    // MARK: - Custom Entity Dialog

    @Published var showingAddCustomEntity: Bool = false
    @Published var prefilledEntityText: String? = nil

    // MARK: - Client Suggestion

    @Published var showClientSuggestion: Bool = false
    @Published var suggestedClientEntity: Entity? = nil
    @Published var clientSuggestionCandidates: [Entity] = []

    /// Identify the most frequently mentioned person as the likely client.
    /// Returns all person anchors sorted by total occurrence count (highest first).
    func identifyClientCandidates() {
        Self.mergeLog("identifyClientCandidates called, allEntities count=\(allEntities.count)")

        // Only suggest if no entity is already classified as personClient
        let existingClients = allEntities.filter { $0.type == .personClient }
        if !existingClients.isEmpty {
            Self.mergeLog("SKIPPED - already has \(existingClients.count) personClient entities: \(existingClients.map { $0.originalText })")
            return
        }

        // Get all person anchor entities
        let personAnchors = allEntities.filter { $0.type.isPerson && $0.isAnchor }
        Self.mergeLog("Person anchors found: \(personAnchors.count) — \(personAnchors.map { "\($0.originalText) (\($0.type))" })")
        guard !personAnchors.isEmpty else {
            Self.mergeLog("SKIPPED - no person anchors")
            return
        }

        // Count total occurrences for each anchor cluster (anchor + its children)
        var clusterCounts: [(anchor: Entity, count: Int)] = []
        for anchor in personAnchors {
            var totalPositions = anchor.positions.count
            // Add children's positions
            if let baseId = anchor.baseId {
                let children = allEntities.filter {
                    $0.id != anchor.id && $0.baseId == baseId && !$0.isAnchor
                }
                for child in children {
                    totalPositions += child.positions.count
                }
            }
            clusterCounts.append((anchor: anchor, count: totalPositions))
        }

        // Sort by count descending
        clusterCounts.sort { $0.count > $1.count }

        // Need at least one candidate
        guard let top = clusterCounts.first else { return }

        suggestedClientEntity = top.anchor
        clientSuggestionCandidates = clusterCounts.map { $0.anchor }
        showClientSuggestion = true
    }

    /// Confirm the selected entity as the client — reclassify to personClient
    func confirmClientSelection(_ entity: Entity) {
        reclassifyEntity(entity.id, to: .personClient)
        showClientSuggestion = false
        suggestedClientEntity = nil
        clientSuggestionCandidates = []
    }

    /// Dismiss client suggestion without action
    func dismissClientSuggestion() {
        showClientSuggestion = false
        suggestedClientEntity = nil
        clientSuggestionCandidates = []
    }

    // MARK: - Initialization

    init() {
        let engine = AnonymizationEngine()
        self.engine = engine
        self.redactState = RedactPhaseState(engine: engine)
        self.cacheManager = HighlightCacheManager()
        self.redactState.cacheManager = cacheManager

        // Forward RedactPhaseState changes to this view model so SwiftUI updates
        cancellable = redactState.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Analysis

    func analyze() async {
        await redactState.analyze()
        rebuildCaches()

        // Auto-show duplicate finder if groups found
        let duplicateGroups = redactState.findPotentialDuplicates()
        if !duplicateGroups.isEmpty {
            redactState.showDuplicateFinderModal = true
        }

        // Always try client suggestion after analysis
        // If duplicate finder is showing, it will trigger again after merge via mergeDuplicateGroups
        if duplicateGroups.isEmpty {
            identifyClientCandidates()
        }
    }

    // MARK: - Multi-Document

    /// Whether the user has saved documents and/or has a current analysis
    var hasAnyContent: Bool {
        !redactState.sourceDocuments.isEmpty || redactState.result != nil
    }

    /// Save current document and clear input for the next one
    func addAnotherDocument() {
        redactState.saveCurrentDocumentAndClearForNext()
    }

    /// Combined redacted text from all source documents + current document
    var combinedRedactedText: String {
        var parts: [String] = []

        // Add previously saved documents
        for doc in redactState.sourceDocuments {
            let header = "=== \(doc.name) ==="
            parts.append("\(header)\n\n\(doc.redactedText)")
        }

        // Add current document if analyzed
        if redactState.result != nil {
            let docNum = redactState.sourceDocuments.count + 1
            let header = "=== Document \(docNum) (\(textInputTypeLabel)) ==="
            parts.append("\(header)\n\n\(redactState.displayedRedactedText)")
        }

        // Single document — use type label as header (no document number)
        if parts.count == 1 && redactState.sourceDocuments.isEmpty {
            return "=== \(textInputTypeLabel) ===\n\n\(redactState.displayedRedactedText)"
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Copy Actions

    func copyRedactedText() {
        ClipboardHelper.copyPlain(combinedRedactedText)
        justCopiedRedacted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.justCopiedRedacted = false
        }
    }

    func copyRestoredText() {
        ClipboardHelper.copyFormatted(restoredText)
        justCopiedRestored = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.justCopiedRestored = false
        }
    }

    // MARK: - Restore

    func restoreNames() {
        guard !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Sync all entity mappings (current + saved docs)
        syncAllEntityMappings()

        // Debug: log what's available for restore
        let allMappings = engine.entityMapping.allMappings
        Self.mergeLog("RESTORE: \(allMappings.count) mappings available")
        for m in allMappings where m.replacement.contains("CLIENT") {
            Self.mergeLog("  RESTORE MAPPING: \(m.replacement) → '\(m.original)'")
        }

        // Find placeholders in pasted text that aren't in mappings
        let mappingCodes = Set(allMappings.map { $0.replacement })
        let pattern = "\\[[A-Z]+_[A-Z0-9]+(?:_[A-Z]+)*\\]"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(pastedText.startIndex..., in: pastedText)
            let matches = regex.matches(in: pastedText, range: range)
            for match in matches {
                if let r = Range(match.range, in: pastedText) {
                    let code = String(pastedText[r])
                    if !mappingCodes.contains(code) {
                        Self.mergeLog("  RESTORE UNMAPPED: \(code)")
                    }
                }
            }
        }

        // Restore placeholders → original text
        restoredText = reidentifier.restore(
            text: pastedText,
            using: engine.entityMapping
        )
    }

    /// Clear restored text to go back to paste-back mode
    func clearRestore() {
        restoredText = ""
    }

    // MARK: - Entity Management (forwarded to redactState)

    /// All entities: current document + saved documents (now unified in redactState.allEntities)
    var allEntities: [Entity] { redactState.allEntities }
    var activeEntities: [Entity] { redactState.activeEntities }
    var result: AnonymizationResult? { redactState.result }
    var isProcessing: Bool { redactState.isProcessing }
    var inputText: String {
        get { redactState.inputText }
        set { redactState.inputText = newValue }
    }
    var textInputType: TextInputType {
        get { redactState.textInputType }
        set { redactState.textInputType = newValue }
    }
    var textInputTypeDescription: String {
        get { redactState.textInputTypeDescription }
        set { redactState.textInputTypeDescription = newValue }
    }

    /// Display label for the current text input type — uses custom description for "Other"
    var textInputTypeLabel: String {
        if textInputType == .other && !textInputTypeDescription.isEmpty {
            return textInputTypeDescription
        }
        return textInputType.rawValue
    }

    // MARK: - Deep Scan

    var isRunningDeepScan: Bool { redactState.isRunningDeepScan }
    var deepScanFindings: [Entity] { redactState.deepScanFindings }
    var deepScanFindingsCount: Int { redactState.deepScanFindingsCount }
    var showDeepScanCompleteMessage: Bool {
        get { redactState.showDeepScanCompleteMessage }
        set { redactState.showDeepScanCompleteMessage = newValue }
    }

    func runDeepScan() async {
        await redactState.runDeepScan()
        rebuildCaches()
    }

    // MARK: - Forwarded Properties (Cache)

    var cachedRedactedAttributed: AttributedString? { cacheManager.cachedRedactedAttributed }
    var cachedOriginalAttributed: AttributedString? { cacheManager.cachedOriginalAttributed }
    var piiReviewFindings: [Entity] { redactState.piiReviewFindings }
    var successMessage: String? {
        get { redactState.successMessage }
        set { redactState.successMessage = newValue }
    }

    func toggleEntity(_ entity: Entity) {
        redactState.toggleEntity(entity)
    }

    func toggleEntities(_ entities: [Entity]) {
        redactState.toggleEntities(entities)
    }

    func isEntityExcluded(_ entity: Entity) -> Bool {
        redactState.isEntityExcluded(entity)
    }

    var hasPendingChanges: Bool { redactState.hasPendingChanges }

    func applyChanges() {
        redactState.applyChanges()
        rebuildCaches()
    }

    func openAddCustomEntity(withText text: String? = nil) {
        prefilledEntityText = text
        showingAddCustomEntity = true
    }

    func addCustomEntity(text: String, type: EntityType) {
        redactState.addCustomEntity(text: text, type: type)
        rebuildCaches()
    }

    func removeEntitiesByText(_ text: String) {
        redactState.removeEntitiesByText(text)
        rebuildCaches()
    }

    func reclassifyEntity(_ entityId: UUID, to newType: EntityType) {
        redactState.reclassifyEntity(entityId, to: newType)
        rebuildCaches()
    }

    // MARK: - Duplicate Finder

    func openDuplicateFinder() {
        redactState.showDuplicateFinderModal = true
    }

    func mergeDuplicateGroups(_ groups: [DuplicateGroup]) {
        for group in groups {
            for match in group.matches {
                mergeEntities(alias: match, into: group.primary, skipCacheRebuild: true)
            }
        }
        rebuildCaches()

        let totalMerged = groups.reduce(0) { $0 + $1.matches.count }
        redactState.successMessage = "Merged \(totalMerged) duplicate\(totalMerged == 1 ? "" : "s") into \(groups.count) group\(groups.count == 1 ? "" : "s")"
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { [weak self] in
                self?.redactState.successMessage = nil
                // After merge completes, suggest client identification
                self?.identifyClientCandidates()
            }
        }
    }

    // MARK: - Entity Merge

    func mergeEntities(alias: Entity, into primary: Entity, skipCacheRebuild: Bool = false) {
        Self.mergeLog("'\(alias.originalText)' (\(alias.type), anchor=\(alias.isAnchor), merged=\(alias.isMergedChild), code=\(alias.replacementCode)) INTO '\(primary.originalText)' (\(primary.type), anchor=\(primary.isAnchor), merged=\(primary.isMergedChild), code=\(primary.replacementCode))")

        // Allow merging across person subtypes (client/provider/other), block other cross-type merges
        guard alias.type == primary.type || (alias.type.isPerson && primary.type.isPerson) else {
            Self.mergeLog("BLOCKED - type mismatch: \(alias.type) vs \(primary.type)")
            return
        }

        // Non-person entities: simple merge
        guard alias.type.isPerson || primary.type.isPerson else {
            Self.mergeLog("Non-person simple merge")
            _ = engine.entityMapping.mergeMapping(alias: alias.originalText, into: primary.originalText)
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)
            return
        }

        // Person entities: try merge with variant detection
        let result = engine.entityMapping.tryMergeMapping(alias: alias.originalText, into: primary.originalText)
        Self.mergeLog("tryMergeMapping result = \(result)")

        switch result {
        case .success:
            Self.mergeLog("Success path → completeMerge")
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)

        case .variantNotDetected:
            Self.mergeLog("variantNotDetected → forcing .first variant")
            _ = engine.entityMapping.completeMergeWithVariant(
                alias: alias.originalText, into: primary.originalText, variant: .first
            )
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)

        case .primaryNotFound, .noBaseId:
            Self.mergeLog("primaryNotFound/noBaseId → fallback mergeMapping")
            _ = engine.entityMapping.mergeMapping(alias: alias.originalText, into: primary.originalText)
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)
        }
        Self.mergeLog("Complete")
    }

    private func completeMerge(alias: Entity, into primary: Entity, skipCacheRebuild: Bool = false) {
        let oldAliasBaseId = alias.baseId

        // Update alias entity's code to the variant code
        if let newAliasCode = engine.entityMapping.existingMapping(for: alias.originalText) {
            redactState.updateEntityReplacementCode(entityId: alias.id, newCode: newAliasCode)
        }

        // Mark the alias as a merged child
        redactState.markEntityAsMergedChild(entityId: alias.id)

        // Transfer orphaned sub-entities from old anchor to new anchor
        if let oldBaseId = oldAliasBaseId, let newBaseId = primary.baseId, oldBaseId != newBaseId {
            let orphanedEntities = redactState.allEntities.filter {
                $0.id != alias.id && $0.baseId == oldBaseId
            }
            for orphan in orphanedEntities {
                let oldCode = orphan.replacementCode
                var variantSuffix = ""
                for variant in NameVariant.allCases {
                    if oldCode.uppercased().hasSuffix(variant.codeSuffix + "]") {
                        variantSuffix = variant.codeSuffix
                        break
                    }
                }
                let newCode = "[\(newBaseId)\(variantSuffix)]"
                redactState.updateEntityReplacementCode(entityId: orphan.id, newCode: newCode)
                redactState.markEntityAsMergedChild(entityId: orphan.id)
            }
        }

        // Move deep scan findings to result if merged
        if redactState.deepScanFindings.contains(where: { $0.id == alias.id }) {
            redactState.moveDeepScanFindingToResult(alias.id)
        }
        if redactState.deepScanFindings.contains(where: { $0.id == primary.id }) {
            redactState.moveDeepScanFindingToResult(primary.id)
        }

        // Update primary's code if it changed
        if let newPrimaryCode = engine.entityMapping.existingMapping(for: primary.originalText),
           newPrimaryCode != primary.replacementCode {
            redactState.updateEntityReplacementCode(entityId: primary.id, newCode: newPrimaryCode)
        }

        redactState.cancelVariantSelection()
        redactState.markRedactedTextNeedsUpdate()

        if !skipCacheRebuild { rebuildCaches() }
    }

    // MARK: - Multi-Document (forwarded)

    var sourceDocuments: [SourceDocument] { redactState.sourceDocuments }

    func deleteSourceDocument(id: UUID) {
        redactState.deleteSourceDocument(id: id)
    }

    // MARK: - Error State (forwarded)

    var errorMessage: String? {
        get { redactState.errorMessage }
        set { redactState.errorMessage = newValue }
    }

    // MARK: - Session Management

    func startNewSession() {
        redactState.clearAll()
        engine.clearSession()
        pastedText = ""
        restoredText = ""
        justCopiedRedacted = false
        justCopiedRestored = false
    }

    // MARK: - Debug Logging

    private static let logFile = "/tmp/redactor_merge.log"

    static func mergeLog(_ msg: String) {
        let line = "[\(Date())] MERGE: \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile) {
                if let handle = FileHandle(forWritingAtPath: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logFile, contents: data)
            }
        }
    }

    // MARK: - Private

    /// Rebuild highlight caches after entity changes
    private func rebuildCaches() {
        guard let result = redactState.result else { return }
        cacheManager.rebuildAllCaches(
            originalText: result.originalText,
            allEntities: redactState.allEntities,
            activeEntities: redactState.activeEntities,
            excludedIds: redactState.excludedEntityIds,
            redactedText: redactState.displayedRedactedText,
            replacementPositions: redactState.replacementPositions,
            restoredText: nil
        )
    }

    /// Register all entity mappings so TextReidentifier can find them
    private func syncAllEntityMappings() {
        // Current document entities
        for entity in redactState.activeEntities {
            engine.entityMapping.syncMapping(
                originalText: entity.originalText,
                replacementCode: entity.replacementCode
            )
        }

        // Saved source document entities
        for doc in redactState.sourceDocuments {
            for entity in doc.entities {
                engine.entityMapping.syncMapping(
                    originalText: entity.originalText,
                    replacementCode: entity.replacementCode
                )
            }
        }
    }
}
