//
//  WorkflowViewModel.swift
//  Redactor
//
//  Purpose: Coordinates the three-phase anonymization workflow
//  Organization: 3 Big Things
//
//  Note: This is the refactored coordinator that delegates to phase-specific state objects:
//  - RedactPhaseState: Handles anonymization and entity management
//  - ImprovePhaseState: Handles AI processing and refinement
//  - RestorePhaseState: Handles re-identification
//  - HighlightCacheManager: Handles AttributedString caching
//

import SwiftUI
import AppKit
import Combine

// MARK: - Workflow ViewModel

/// Coordinator for the three-phase anonymization workflow
/// Delegates to phase-specific state objects for cleaner separation of concerns
@MainActor
class WorkflowViewModel: ObservableObject {

    // MARK: - Phase State Objects

    var redactState: RedactPhaseState
    let improveState: ImprovePhaseState
    var restoreState: RestorePhaseState
    let cacheManager: HighlightCacheManager

    // MARK: - Workflow Navigation

    @Published var currentPhase: WorkflowPhase = .redact

    // MARK: - Services

    let engine: AnonymizationEngine
    let aiService: AIAssistantService

    // MARK: - Change Forwarding

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(engine: AnonymizationEngine, aiService: AIAssistantService) {
        self.engine = engine
        self.aiService = aiService
        self.cacheManager = HighlightCacheManager()
        self.redactState = RedactPhaseState(engine: engine)
        self.improveState = ImprovePhaseState(aiService: aiService)
        self.restoreState = RestorePhaseState()

        // Wire up dependencies
        redactState.cacheManager = cacheManager
        restoreState.cacheManager = cacheManager

        // Configure callbacks
        improveState.getRedactedText = { [weak self] in
            guard let self = self else { return "" }
            // Use source documents if available, otherwise fall back to current redacted text
            if !self.improveState.sourceDocuments.isEmpty {
                return self.improveState.formatSourceDocumentsForAI()
            }
            return self.redactState.displayedRedactedText
        }

        restoreState.getAIOutput = { [weak self] in
            self?.improveState.currentDocument ?? ""
        }

        improveState.getTextInputType = { [weak self] in
            self?.redactState.textInputType ?? .otherReports
        }

        restoreState.getEntityMapping = { [weak self] in
            self?.engine.entityMapping
        }

        // Forward changes from child state objects to trigger view updates
        redactState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        improveState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        restoreState.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        cacheManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    convenience init() {
        let engine = AnonymizationEngine()
        let bedrockService = BedrockService()
        let credentialsManager = AWSCredentialsManager.shared
        let aiService = AIAssistantService(bedrockService: bedrockService, credentialsManager: credentialsManager)
        self.init(engine: engine, aiService: aiService)

        Task {
            if let credentials = credentialsManager.loadCredentials() {
                try? await bedrockService.configure(with: credentials)
            }
        }
    }

    // MARK: - Bindable Properties (need @Published for SwiftUI $ bindings)
    // These sync with state objects via didSet

    @Published var inputText: String = "" {
        didSet { redactState.inputText = inputText }
    }

    @Published var showingAddCustom: Bool = false {
        didSet { redactState.showingAddCustom = showingAddCustom }
    }

    @Published var refinementInput: String = "" {
        didSet { improveState.refinementInput = refinementInput }
    }

    @Published var customInstructions: String = "" {
        didSet { improveState.customInstructions = customInstructions }
    }

    @Published var showPromptEditor: Bool = false {
        didSet { improveState.showPromptEditor = showPromptEditor }
    }

    @Published var showAddCustomCategory: Bool = false {
        didSet { improveState.showAddCustomCategory = showAddCustomCategory }
    }

    // MARK: - Forwarded Properties (Redact Phase)

    var result: AnonymizationResult? { redactState.result }
    var isProcessing: Bool { redactState.isProcessing }
    var estimatedSeconds: Int { redactState.estimatedSeconds }
    var statusMessage: String { redactState.statusMessage }

    var errorMessage: String? {
        get { redactState.errorMessage ?? improveState.aiError ?? restoreState.errorMessage }
        set {
            redactState.errorMessage = newValue
            improveState.aiError = nil
            restoreState.errorMessage = nil
        }
    }

    var successMessage: String? {
        get { redactState.successMessage }
        set { redactState.successMessage = newValue }
    }

    var excludedEntityIds: Set<UUID> { redactState.excludedEntityIds }
    var customEntities: [Entity] { redactState.customEntities }
    var piiReviewFindings: [Entity] { redactState.piiReviewFindings }
    var isReviewingPII: Bool { redactState.isReviewingPII }
    var piiReviewError: String? { redactState.piiReviewError }

    var deepScanFindings: [Entity] { redactState.deepScanFindings }
    var isRunningDeepScan: Bool { redactState.isRunningDeepScan }
    var deepScanError: String? { redactState.deepScanError }

    var gliNERFindings: [Entity] { redactState.gliNERFindings }
    var isRunningGLiNERScan: Bool { redactState.isRunningGLiNERScan }
    var gliNERScanError: String? { redactState.gliNERScanError }

    var cachedRedactedText: String { redactState.cachedRedactedText }

    var prefilledText: String? {
        get { redactState.prefilledText }
        set { redactState.prefilledText = newValue }
    }

    var justCopiedAnonymized: Bool { redactState.justCopiedAnonymized }
    var justCopiedOriginal: Bool { redactState.justCopiedOriginal }
    var hasCopiedRedacted: Bool { redactState.hasCopiedRedacted }
    var hasPendingChanges: Bool { redactState.hasPendingChanges }

    // MARK: - Forwarded Properties (Multi-Document)

    var sourceDocuments: [SourceDocument] { redactState.sourceDocuments }

    // MARK: - Forwarded Properties (Improve Phase)

    var selectedDocumentType: DocumentType? {
        get { improveState.selectedDocumentType }
        set { improveState.selectedDocumentType = newValue }
    }

    var sliderSettings: SliderSettings {
        get { improveState.sliderSettings }
        set { improveState.sliderSettings = newValue }
    }

    var aiOutput: String { improveState.aiOutput }
    var isAIProcessing: Bool { improveState.isAIProcessing }
    var aiError: String? { improveState.aiError }
    var isInRefinementMode: Bool { improveState.isInRefinementMode }

    var chatHistory: [(role: String, content: String)] { improveState.chatHistory }
    var streamingDestination: StreamingDestination { improveState.streamingDestination }
    var currentDocument: String { improveState.currentDocument }
    var previousDocument: String { improveState.previousDocument }
    var changedLineIndices: Set<Int> { improveState.changedLineIndices }

    var documentTypeToEdit: DocumentType? {
        get { improveState.documentTypeToEdit }
        set { improveState.documentTypeToEdit = newValue }
    }

    // MARK: - Forwarded Properties (Restore Phase)

    var finalRestoredText: String { restoreState.finalRestoredText }
    var hasRestoredText: Bool { restoreState.hasRestoredText }
    var justCopiedRestored: Bool { restoreState.justCopiedRestored }

    // MARK: - Forwarded Properties (Cache Manager)

    var cachedOriginalAttributed: AttributedString? { cacheManager.cachedOriginalAttributed }
    var cachedRedactedAttributed: AttributedString? { cacheManager.cachedRedactedAttributed }
    var cachedRestoredAttributed: AttributedString? { cacheManager.cachedRestoredAttributed }

    // MARK: - Computed Properties

    var allEntities: [Entity] { redactState.allEntities }
    var activeEntities: [Entity] { redactState.activeEntities }

    /// Entities actually restored in the output - only those whose placeholders appear in the document
    /// Deduplicates by originalText to avoid showing same entity multiple times
    var restoredEntities: [Entity] {
        let output = currentDocument
        guard !output.isEmpty else { return [] }

        var seen = Set<String>()
        var result: [Entity] = []

        // First add entities from source documents (multi-doc flow)
        for doc in improveState.sourceDocuments {
            for entity in doc.entities {
                // Only include if placeholder appears in document
                guard output.contains(entity.replacementCode) else { continue }

                let key = entity.originalText.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(entity)
                }
            }
        }

        // Then add current active entities (single-doc flow or unsaved current doc)
        for entity in redactState.activeEntities {
            // Only include if placeholder appears in document
            guard output.contains(entity.replacementCode) else { continue }

            let key = entity.originalText.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(entity)
            }
        }

        return result
    }

    /// Missing entities - placeholders in the restored text that have no replacement
    /// These are typically AI-generated placeholders that weren't in the original redaction
    var missingEntities: [(placeholder: String, override: String?)] {
        let output = finalRestoredText
        guard !output.isEmpty else { return [] }

        // Broad pattern to match any placeholder format: [WORD_X...] or [WORD_X_WORD...]
        let pattern = "\\[[A-Z]+_[A-Z](?:_[A-Z]+)*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)

        // Get all replacement codes from restored entities
        let restoredCodes = Set(restoredEntities.map { $0.replacementCode })

        var seen = Set<String>()
        var result: [(placeholder: String, override: String?)] = []

        for match in matches {
            guard let matchRange = Range(match.range, in: output) else { continue }
            let placeholder = String(output[matchRange])

            // Skip if already in restored entities (it has an original)
            guard !restoredCodes.contains(placeholder) else { continue }

            // Skip duplicates
            guard !seen.contains(placeholder) else { continue }
            seen.insert(placeholder)

            // Check if user has provided an override
            let override = restoreState.replacementOverrides[placeholder]
            result.append((placeholder: placeholder, override: override))
        }

        return result
    }

    func isEntityExcluded(_ entity: Entity) -> Bool {
        redactState.isEntityExcluded(entity)
    }

    var displayedRedactedText: String { redactState.displayedRedactedText }
    var canContinueFromRedact: Bool { redactState.canContinue }
    var canContinueFromImprove: Bool { improveState.canContinue }
    var hasGeneratedOutput: Bool { improveState.hasGeneratedOutput }
    var inputChangedSinceGeneration: Bool { improveState.inputChangedSinceGeneration }

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
            // If going back from Improve to Redact, cleanup AI state
            if currentPhase == .improve && previous == .redact {
                // Cancel AI tasks and reset improve state
                improveState.cancelAndCleanup()

                // Remove the doc that was saved when we went forward
                // (undo the saveCurrentDocumentOnly() from continueToNextPhase)
                if !redactState.sourceDocuments.isEmpty {
                    redactState.sourceDocuments.removeLast()
                }
            }
            currentPhase = previous
        }
    }

    func continueToNextPhase() {
        switch currentPhase {
        case .redact:
            guard canContinueFromRedact else { return }

            // Save current document WITHOUT clearing (keep state for back navigation)
            if redactState.result != nil {
                redactState.saveCurrentDocumentOnly()
            }

            // Transfer source documents to improve phase
            improveState.sourceDocuments = redactState.sourceDocuments

            // DON'T clear inputText or caches - keep them for back navigation
            currentPhase = .improve
        case .improve:
            guard canContinueFromImprove else { return }
            restoreNamesFromAIOutput()
            currentPhase = .restore
        case .restore:
            break
        }
    }

    // MARK: - Redact Phase Actions

    func analyze() async {
        let totalStart = CFAbsoluteTimeGetCurrent()
        await redactState.analyze()

        // Rebuild cache using strong reference to cacheManager
        if let result = redactState.result {
            let cacheStart = CFAbsoluteTimeGetCurrent()
            cacheManager.rebuildAllCaches(
                originalText: result.originalText,
                allEntities: redactState.allEntities,
                activeEntities: redactState.activeEntities,
                excludedIds: redactState.excludedEntityIds,
                redactedText: redactState.displayedRedactedText,
                replacementPositions: redactState.replacementPositions,
                restoredText: nil
            )
            print("⏱️ WorkflowVM cacheManager.rebuildAllCaches: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - cacheStart))s")
        }
        print("⏱️ WorkflowVM.analyze() TOTAL: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - totalStart))s")

        // Auto-show duplicate finder if groups found
        let dupeStart = CFAbsoluteTimeGetCurrent()
        let duplicateGroups = redactState.findPotentialDuplicates()
        print("⏱️ findPotentialDuplicates: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - dupeStart))s")
        if !duplicateGroups.isEmpty {
            redactState.showDuplicateFinderModal = true
        }
    }

    func clearAll() {
        // Reset @Published bindable properties
        inputText = ""
        showingAddCustom = false
        refinementInput = ""
        customInstructions = ""
        showPromptEditor = false
        showAddCustomCategory = false

        // Clear child state objects
        redactState.clearAll()
        improveState.clearAll()
        restoreState.clearAll()
        cacheManager.clearAll()
        currentPhase = .redact
    }

    func toggleEntity(_ entity: Entity) {
        redactState.toggleEntity(entity)
    }

    func toggleEntities(_ entities: [Entity]) {
        redactState.toggleEntities(entities)
    }

    /// Merge one entity into another (alias adopts primary's replacement code)
    /// The alias entity is removed from the list, its positions added to primary
    /// If variant detection fails, shows prompt for user to select variant
    /// - Parameter skipCacheRebuild: If true, skips cache rebuild (for batch operations)
    func mergeEntities(alias: Entity, into primary: Entity, skipCacheRebuild: Bool = false) {
        guard alias.type == primary.type else {
            #if false  // DEBUG disabled for perf testing
            // print("WorkflowViewModel.mergeEntities: Cannot merge different entity types")
            #endif
            return
        }

        // Non-person entities: skip variant detection, use simple merge
        guard alias.type.isPerson else {
            _ = engine.entityMapping.mergeMapping(alias: alias.originalText, into: primary.originalText)
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)
            return
        }

        // Person entities: try merge with variant detection
        let result = engine.entityMapping.tryMergeMapping(alias: alias.originalText, into: primary.originalText)

        #if false  // DEBUG disabled for perf testing
        // print("WorkflowViewModel.mergeEntities: '\(alias.originalText)' into '\(primary.originalText)'")
        print("  tryMergeMapping result: \(result)")
        #endif

        switch result {
        case .success(let code, let variant):
            // Variant detected, proceed with merge
            #if false  // DEBUG disabled for perf testing
            print("  ✓ Auto-detected variant: \(variant) → \(code)")
            #endif
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)

        case .variantNotDetected(let baseId, _):
            // Auto-assign .first and complete merge (modal no longer needed)
            // Restoration uses RedactedPerson which has all variants
            #if false  // DEBUG disabled for perf testing
            print("  ⚠️ Variant not detected, auto-assigning .first (baseId: \(baseId))")
            #endif
            _ = engine.entityMapping.completeMergeWithVariant(
                alias: alias.originalText,
                into: primary.originalText,
                variant: .first
            )
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)

        case .primaryNotFound:
            // Fallback to old behavior using mergeMapping()
            #if false  // DEBUG disabled for perf testing
            print("  ⚠️ Primary not found, using fallback")
            #endif
            _ = engine.entityMapping.mergeMapping(alias: alias.originalText, into: primary.originalText)
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)

        case .noBaseId:
            // Fallback to old behavior using mergeMapping()
            #if false  // DEBUG disabled for perf testing
            print("  ⚠️ No baseId, using fallback")
            #endif
            _ = engine.entityMapping.mergeMapping(alias: alias.originalText, into: primary.originalText)
            completeMerge(alias: alias, into: primary, skipCacheRebuild: skipCacheRebuild)
        }
    }

    /// Complete merge after variant is determined (either auto-detected or user-selected)
    /// Instead of removing the alias, we update its code to the variant code and keep both entities
    /// - Parameter skipCacheRebuild: If true, skips cache rebuild (for batch operations)
    func completeMerge(alias: Entity, into primary: Entity, skipCacheRebuild: Bool = false) {
        #if DEBUG
        print("🔀 completeMerge START: '\(alias.originalText)' into '\(primary.originalText)'")
        print("   Alias in deepScan: \(redactState.deepScanFindings.contains { $0.id == alias.id })")
        print("   Alias in result: \(redactState.result?.entities.contains { $0.id == alias.id } ?? false)")
        #endif

        // IMPORTANT: Capture alias's old baseId BEFORE it gets a new code
        let oldAliasBaseId = alias.baseId

        // Get the alias's updated code from the mapping (this is the variant code)
        if let newAliasCode = engine.entityMapping.existingMapping(for: alias.originalText) {
            // Update the alias entity's code to the variant code (e.g., [PERSON_A_FIRST])
            // This keeps both entities in the list with correct codes
            redactState.updateEntityReplacementCode(entityId: alias.id, newCode: newAliasCode)

            #if false  // DEBUG disabled for perf testing
            print("   Updated code: \(alias.replacementCode) → \(newAliasCode)")
            #endif
        } else {
            #if false  // DEBUG disabled for perf testing
            print("   No mapping found - keeping code \(alias.replacementCode)")
            #endif
        }

        // Mark the alias as a merged child so it displays as a sub-entity
        redactState.markEntityAsMergedChild(entityId: alias.id)

        // Transfer any orphaned sub-entities that belonged to the alias
        if let oldBaseId = oldAliasBaseId, let newBaseId = primary.baseId, oldBaseId != newBaseId {
            // Find all entities that still have the old baseId (they're now orphans)
            let orphanedEntities = redactState.allEntities.filter {
                $0.id != alias.id && $0.baseId == oldBaseId
            }

            for orphan in orphanedEntities {
                // Extract variant suffix from old code
                let oldCode = orphan.replacementCode
                var variantSuffix = ""
                for variant in NameVariant.allCases {
                    if oldCode.uppercased().hasSuffix(variant.codeSuffix + "]") {
                        variantSuffix = variant.codeSuffix
                        break
                    }
                }

                // Build new code with primary's baseId
                let newCode = "[\(newBaseId)\(variantSuffix)]"
                redactState.updateEntityReplacementCode(entityId: orphan.id, newCode: newCode)
                redactState.markEntityAsMergedChild(entityId: orphan.id)

                #if DEBUG
                print("   Transferred orphan: '\(orphan.originalText)' \(oldCode) → \(newCode)")
                #endif
            }
        }

        // If alias is a deep scan finding, move it to result.entities
        // so it appears in the main section (not the deep scan section)
        if redactState.deepScanFindings.contains(where: { $0.id == alias.id }) {
            redactState.moveDeepScanFindingToResult(alias.id)
            #if false  // DEBUG disabled for perf testing
            print("   Moved alias from deepScan to result")
            #endif
        }

        // If primary (anchor) is in deep scan, move it to result.entities
        // so anchor and child are in the same section for grouping
        if redactState.deepScanFindings.contains(where: { $0.id == primary.id }) {
            redactState.moveDeepScanFindingToResult(primary.id)
            #if false  // DEBUG disabled for perf testing
            print("   Moved primary from deepScan to result")
            #endif
        }

        // Also update primary's code if it changed
        if let newPrimaryCode = engine.entityMapping.existingMapping(for: primary.originalText),
           newPrimaryCode != primary.replacementCode {
            redactState.updateEntityReplacementCode(entityId: primary.id, newCode: newPrimaryCode)
            #if false  // DEBUG disabled for perf testing
            print("   Updated primary code: \(primary.replacementCode) → \(newPrimaryCode)")
            #endif
        }

        #if DEBUG
        // Check final state
        if let updatedAlias = redactState.allEntities.first(where: { $0.id == alias.id }) {
            print("   FINAL: '\(updatedAlias.originalText)' code=\(updatedAlias.replacementCode) variant=\(updatedAlias.nameVariant?.rawValue ?? "nil") isMergedChild=\(updatedAlias.isMergedChild) isAnchor=\(updatedAlias.isAnchor) baseId=\(updatedAlias.baseId ?? "nil")")
        } else {
            print("   ⚠️ FINAL: Alias NOT found in allEntities!")
        }
        // Check primary state
        if let updatedPrimary = redactState.allEntities.first(where: { $0.id == primary.id }) {
            print("   PRIMARY: '\(updatedPrimary.originalText)' code=\(updatedPrimary.replacementCode) nameVariant=\(updatedPrimary.nameVariant?.rawValue ?? "nil") isAnchor=\(updatedPrimary.isAnchor) isMergedChild=\(updatedPrimary.isMergedChild)")
        } else {
            print("   ⚠️ PRIMARY NOT FOUND: '\(primary.originalText)'")
        }
        #endif

        // Close variant selection modal if open
        redactState.cancelVariantSelection()

        // Mark text as needing update
        redactState.markRedactedTextNeedsUpdate()

        // Rebuild caches with updated entities (unless skipped for batch operations)
        if !skipCacheRebuild, let result = redactState.result {
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
    }


    /// Reclassify entity to a new type (pass-through to RedactPhaseState)
    func reclassifyEntity(_ entityId: UUID, to newType: EntityType) {
        redactState.reclassifyEntity(entityId, to: newType)

        // Rebuild caches with updated entities
        if let result = redactState.result {
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
    }

    /// Open the duplicate finder modal
    func openDuplicateFinder() {
        redactState.showDuplicateFinderModal = true
    }

    /// Merge multiple duplicate groups at once
    func mergeDuplicateGroups(_ groups: [DuplicateGroup]) {
        let mergeStart = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        print("🔀 mergeDuplicateGroups called with \(groups.count) groups")
        print("   Entity count BEFORE merge: \(redactState.allEntities.count)")
        for (i, group) in groups.enumerated() {
            print("   Group \(i): primary='\(group.primary.originalText)' matches=\(group.matches.map { $0.originalText })")
        }
        #endif

        for group in groups {
            // Merge each match into the primary entity (skip cache rebuild in loop)
            for match in group.matches {
                mergeEntities(alias: match, into: group.primary, skipCacheRebuild: true)
            }
        }

        // Rebuild caches ONCE after all merges complete
        if let result = redactState.result {
            let cacheStart = CFAbsoluteTimeGetCurrent()
            cacheManager.rebuildAllCaches(
                originalText: result.originalText,
                allEntities: redactState.allEntities,
                activeEntities: redactState.activeEntities,
                excludedIds: redactState.excludedEntityIds,
                redactedText: redactState.displayedRedactedText,
                replacementPositions: redactState.replacementPositions,
                restoredText: nil
            )
            print("⏱️ mergeDuplicateGroups cacheManager.rebuildAllCaches: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - cacheStart))s")
        }

        #if DEBUG
        print("   Entity count AFTER merge: \(redactState.allEntities.count)")
        print("   Remaining entities: \(redactState.allEntities.map { $0.originalText })")
        #endif

        // Show success message
        let totalMerged = groups.reduce(0) { $0 + $1.matches.count }
        redactState.successMessage = "Merged \(totalMerged) duplicate\(totalMerged == 1 ? "" : "s") into \(groups.count) group\(groups.count == 1 ? "" : "s")"
        print("⏱️ mergeDuplicateGroups TOTAL: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - mergeStart))s")

        // Auto-hide success message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                redactState.successMessage = nil
            }
        }
    }

    func applyChanges() {
        let totalStart = CFAbsoluteTimeGetCurrent()
        redactState.applyChanges()
        if let result = redactState.result {
            let cacheStart = CFAbsoluteTimeGetCurrent()
            cacheManager.rebuildAllCaches(
                originalText: result.originalText,
                allEntities: redactState.allEntities,
                activeEntities: redactState.activeEntities,
                excludedIds: redactState.excludedEntityIds,
                redactedText: redactState.displayedRedactedText,
                replacementPositions: redactState.replacementPositions,
                restoredText: nil
            )
            print("⏱️ applyChanges cacheManager.rebuildAllCaches: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - cacheStart))s")
        }
        print("⏱️ applyChanges() TOTAL: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - totalStart))s")
    }

    func openAddCustomEntity(withText text: String? = nil) {
        prefilledText = text
        showingAddCustom = true
    }

    func removeEntitiesByText(_ text: String) {
        redactState.removeEntitiesByText(text)
        if let result = redactState.result {
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
    }

    func addCustomEntity(text: String, type: EntityType) {
        redactState.addCustomEntity(text: text, type: type)
        if let result = redactState.result {
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
    }

    func runLocalPIIReview() async {
        await redactState.runLocalPIIReview()
        if let result = redactState.result {
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
    }

    func runDeepScan() async {
        await redactState.runDeepScan()
        if let result = redactState.result {
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
    }

    func runGLiNERScan() async {
        await redactState.runGLiNERScan()
        if let result = redactState.result {
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
    }

    // MARK: - Multi-Document Actions

    func saveCurrentDocumentAndAddMore() {
        redactState.saveCurrentDocumentAndClearForNext()
        cacheManager.clearAll()
        // Also clear the ViewModel's inputText since it's a separate @Published property
        inputText = ""
    }

    func deleteSourceDocument(id: UUID) {
        redactState.deleteSourceDocument(id: id)
    }

    func updateSourceDocumentDescription(id: UUID, description: String) {
        redactState.updateSourceDocumentDescription(id: id, description: description)
    }

    // MARK: - Improve Phase Actions

    func processWithAI() {
        improveState.processWithAI()
    }

    func sendRefinement() {
        improveState.sendRefinement()
        refinementInput = ""  // Clear the bound property
    }

    func exitRefinementMode() {
        improveState.exitRefinementMode()
        refinementInput = ""
    }

    func regenerateAIOutput() {
        improveState.regenerateAIOutput()
        refinementInput = ""
    }

    func startOverAI() {
        improveState.startOver()
        refinementInput = ""
        customInstructions = ""
    }

    func cancelAIRequest() {
        improveState.cancelAIRequest()
    }

    func editPrompt(for docType: DocumentType) {
        improveState.documentTypeToEdit = docType
        showPromptEditor = true  // Set on ViewModel so sheet binding works
    }

    func openAddCustomCategory() {
        improveState.openAddCustomCategory()
    }

    // MARK: - Restore Phase Actions

    func restoreNamesFromAIOutput() {
        // Ensure all source document entities are in the mapping for multi-doc flow
        // Always add to ensure the entity's exact replacement code is in allMappings
        // (handles cases where entity has different code than existing mapping)
        for doc in improveState.sourceDocuments {
            for entity in doc.entities {
                engine.entityMapping.addMapping(
                    originalText: entity.originalText,
                    replacementCode: entity.replacementCode
                )
            }
        }

        // Detect AI-generated placeholders that weren't in original redacted text
        // These appear when AI creates person references without names in source
        detectAIGeneratedPlaceholders(in: improveState.currentDocument)

        restoreState.restoreNamesFromAIOutput()
        // Rebuild restored text cache using strong reference
        if !restoreState.finalRestoredText.isEmpty {
            cacheManager.rebuildRestoredCache(restoredText: restoreState.finalRestoredText)
        }
    }

    /// Detect person-type placeholders in AI output that weren't in original redacted text
    /// These are added to entityMapping with empty original for user to fill in during Restore
    private func detectAIGeneratedPlaceholders(in text: String) {
        // Match person-type placeholders: [PERSON_A_FIRST], [CLIENT_B_FIRST_LAST], etc.
        let pattern = "\\[(PERSON|CLIENT|PROVIDER|CLINICIAN)_[A-Z](?:_(?:FIRST|LAST|MIDDLE|FIRST_LAST|FULL))*\\]"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let placeholder = String(text[matchRange])

            // Add to mapping if not already present (will have empty original)
            engine.entityMapping.addAIGeneratedPlaceholder(placeholder)
        }
    }

    // MARK: - Copy Actions

    func copyInputText() {
        redactState.copyInputText()
    }

    func copyAnonymizedText() {
        redactState.copyAnonymizedText()
    }

    func copyRestoredText() {
        restoreState.copyRestoredText()
    }

    func copyCurrentDocument() {
        improveState.copyCurrentDocument()
    }

    func dismissError() {
        redactState.dismissError()
        improveState.dismissError()
        restoreState.dismissError()
    }

    func dismissSuccess() {
        redactState.dismissSuccess()
    }

    // MARK: - Cache Management

    func rebuildAllHighlightCaches() {
        cacheManager.rebuildAllCaches(
            originalText: result?.originalText,
            allEntities: allEntities,
            activeEntities: activeEntities,
            excludedIds: excludedEntityIds,
            redactedText: displayedRedactedText,
            replacementPositions: redactState.replacementPositions,
            restoredText: finalRestoredText.isEmpty ? nil : finalRestoredText
        )
    }
}
