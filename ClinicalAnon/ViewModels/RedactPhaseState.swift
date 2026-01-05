//
//  RedactPhaseState.swift
//  Redactor
//
//  Purpose: Manages state for the Redact phase of the workflow
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Duplicate Detection Models

enum DuplicateConfidence: String {
    case high = "High"
    case low = "Low"
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let primary: Entity  // The most complete name (anchor)
    let matches: [Entity]  // Entities to merge into primary
    let confidence: DuplicateConfidence
    var isSelected: Bool = true  // Default to selected for convenience
}

struct NameComponents {
    let original: String
    let normalized: String  // Lowercase, trimmed
    let parts: [String]     // Split by space, titles removed
    let firstName: String?
    let lastName: String?
    let middleNames: [String]
    let hasTitle: Bool

    static let titles = ["mr", "mrs", "ms", "dr", "prof", "miss", "mr.", "mrs.", "ms.", "dr.", "prof."]

    init(from text: String) {
        self.original = text
        self.normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove titles
        var parts = normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let hasTitle = !parts.isEmpty && Self.titles.contains(parts[0])
        if hasTitle {
            parts.removeFirst()
        }
        self.hasTitle = hasTitle
        self.parts = parts

        // Extract name components
        if parts.count >= 1 {
            self.firstName = parts[0]
        } else {
            self.firstName = nil
        }

        if parts.count >= 2 {
            self.lastName = parts[parts.count - 1]
        } else {
            self.lastName = nil
        }

        if parts.count >= 3 {
            self.middleNames = Array(parts[1..<parts.count - 1])
        } else {
            self.middleNames = []
        }
    }
}

// MARK: - Redact Phase State

/// State management for the Redact (anonymization) phase
@MainActor
class RedactPhaseState: ObservableObject {

    // MARK: - Input/Output

    @Published var inputText: String = ""
    @Published var result: AnonymizationResult?

    // MARK: - Text Classification

    @Published var textInputType: TextInputType = .roughNotes
    @Published var textInputTypeDescription: String = ""  // For "Other" type

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

    // Deep Scan (Apple NER at 0.75 confidence)
    @Published var deepScanFindings: [Entity] = []
    @Published var isRunningDeepScan: Bool = false
    @Published var deepScanError: String?
    @Published var showDeepScanCompleteMessage: Bool = false
    @Published var deepScanFindingsCount: Int = 0

    // Private backing store for excluded IDs (pending changes)
    private var _excludedIds: Set<UUID> = []
    @Published var hasPendingChanges: Bool = false

    // MARK: - Cached Text

    @Published private(set) var cachedRedactedText: String = ""
    private var redactedTextNeedsUpdate: Bool = true

    /// Mark that redacted text needs to be regenerated
    func markRedactedTextNeedsUpdate() {
        redactedTextNeedsUpdate = true
    }

    /// Positions of replacement codes in redacted text (for efficient highlighting)
    private(set) var replacementPositions: [(range: NSRange, entityType: EntityType)] = []

    // MARK: - UI State

    @Published var showingAddCustom: Bool = false
    @Published var prefilledText: String? = nil

    // Duplicate Finder
    @Published var showDuplicateFinderModal: Bool = false
    @Published var duplicateGroups: [DuplicateGroup] = []

    // Edit Name Structure Modal
    @Published var isEditingNameStructure: Bool = false
    @Published var nameStructureEditEntity: Entity? = nil

    // Variant Selection Modal (shown when merge variant detection fails)
    @Published var isSelectingVariant: Bool = false
    @Published var variantSelectionAlias: Entity? = nil
    @Published var variantSelectionPrimary: Entity? = nil

    // MARK: - Duplicate Detection

    /// Find potential duplicate person entities based on name overlap
    /// High confidence: Full name (2+ parts) exists as anchor with matching components
    /// Low confidence: Partial matches without full name anchor
    /// Never shown: Different first names + same last name (family filter)
    /// Never shown: Ambiguous partial names (shared across multiple anchors)
    func findPotentialDuplicates() -> [DuplicateGroup] {
        // Filter to person entities only
        let personEntities = allEntities.filter { $0.type.isPerson && !isEntityExcluded($0) }
        guard personEntities.count >= 2 else { return [] }

        // Extract name components for each entity
        var entityComponents: [(entity: Entity, components: NameComponents)] = []
        for entity in personEntities {
            let components = NameComponents(from: entity.originalText)
            // Skip entities with no usable name parts (e.g., just "Dr")
            guard !components.parts.isEmpty else { continue }
            entityComponents.append((entity, components))
        }

        // Find full names (2+ parts) to use as anchors
        let fullNames = entityComponents.filter { $0.components.parts.count >= 2 }

        // Build sets of shared first/last names (names appearing in multiple anchors)
        // These are ambiguous and should NOT be auto-matched in duplicate finder
        let firstNameGroups = Dictionary(grouping: fullNames) { $0.components.firstName?.lowercased() ?? "" }
        let lastNameGroups = Dictionary(grouping: fullNames) { $0.components.lastName?.lowercased() ?? "" }

        let sharedFirstNames = Set(firstNameGroups.filter { $0.key != "" && $0.value.count > 1 }.keys)
        let sharedLastNames = Set(lastNameGroups.filter { $0.key != "" && $0.value.count > 1 }.keys)


        var groups: [DuplicateGroup] = []
        var processedEntityIds: Set<UUID> = []

        // Track ambiguous matches separately (for low confidence groups)
        var ambiguousMatches: [UUID: [(anchor: Entity, match: Entity)]] = [:]

        // High confidence: Match against full names
        for fullName in fullNames {
            guard !processedEntityIds.contains(fullName.entity.id) else { continue }

            var matches: [Entity] = []

            for other in entityComponents {
                guard other.entity.id != fullName.entity.id else { continue }
                guard !processedEntityIds.contains(other.entity.id) else { continue }

                // Skip if same replacement code (already merged)
                if other.entity.replacementCode == fullName.entity.replacementCode { continue }

                // Apply family filter: different first name + same last name = skip
                if let fullFirst = fullName.components.firstName,
                   let otherFirst = other.components.firstName,
                   let fullLast = fullName.components.lastName,
                   let otherLast = other.components.lastName {
                    // Both have first and last names
                    if fullFirst != otherFirst && fullLast == otherLast {
                        // Different people (family members), skip
                        continue
                    }
                }

                // Check for component overlap (with shared name filtering)
                let matchResult = isNameMatch(fullName: fullName.components, partial: other.components,
                                              sharedFirstNames: sharedFirstNames, sharedLastNames: sharedLastNames)

                switch matchResult {
                case .match:
                    matches.append(other.entity)
                    processedEntityIds.insert(other.entity.id)
                case .ambiguousMatch:
                    // Track ambiguous match for low confidence group
                    // Key by the partial name entity so we can show all possible anchors
                    if ambiguousMatches[other.entity.id] == nil {
                        ambiguousMatches[other.entity.id] = []
                    }
                    ambiguousMatches[other.entity.id]?.append((anchor: fullName.entity, match: other.entity))
                case .noMatch:
                    break
                }
            }

            if !matches.isEmpty {
                processedEntityIds.insert(fullName.entity.id)
                groups.append(DuplicateGroup(
                    primary: fullName.entity,
                    matches: matches,
                    confidence: .high
                ))
            }
        }

        // Convert ambiguous matches to low confidence groups
        // Create one group per anchor - full name is primary, partial is merged into it
        for (partialId, matchPairs) in ambiguousMatches {
            guard !processedEntityIds.contains(partialId) else { continue }

            // Create a group for each anchor (full name as primary)
            // User can choose which full name the partial should merge into
            for matchPair in matchPairs {
                guard !processedEntityIds.contains(matchPair.anchor.id) else { continue }

                groups.append(DuplicateGroup(
                    primary: matchPair.anchor,   // Full name as primary (more detail)
                    matches: [matchPair.match],  // Partial name merged into it (less detail)
                    confidence: .low
                ))
            }
            processedEntityIds.insert(partialId)
        }

        // Low confidence: Partial matches without full name anchor
        let partialNames = entityComponents.filter { $0.components.parts.count == 1 }
        var lowConfidenceGroups: [UUID: (primary: Entity, matches: [Entity])] = [:]

        for partial in partialNames {
            guard !processedEntityIds.contains(partial.entity.id) else { continue }

            for other in partialNames {
                guard other.entity.id != partial.entity.id else { continue }
                guard !processedEntityIds.contains(other.entity.id) else { continue }

                // Skip if same replacement code
                if other.entity.replacementCode == partial.entity.replacementCode { continue }

                // Check for partial overlap (e.g., "Sean" and "Sean V")
                if partial.components.firstName == other.components.firstName ||
                   partial.components.parts[0].hasPrefix(other.components.parts[0]) ||
                   other.components.parts[0].hasPrefix(partial.components.parts[0]) {

                    // Group by the longer name
                    let (primary, match) = partial.components.parts[0].count >= other.components.parts[0].count
                        ? (partial.entity, other.entity)
                        : (other.entity, partial.entity)

                    if var existing = lowConfidenceGroups[primary.id] {
                        if !existing.matches.contains(where: { $0.id == match.id }) {
                            existing.matches.append(match)
                            lowConfidenceGroups[primary.id] = existing
                        }
                    } else {
                        lowConfidenceGroups[primary.id] = (primary: primary, matches: [match])
                    }
                }
            }
        }

        // Convert low confidence groups and filter out single matches
        for (_, group) in lowConfidenceGroups {
            guard !processedEntityIds.contains(group.primary.id) else { continue }
            guard !group.matches.allSatisfy({ processedEntityIds.contains($0.id) }) else { continue }

            let validMatches = group.matches.filter { !processedEntityIds.contains($0.id) }
            if !validMatches.isEmpty {
                processedEntityIds.insert(group.primary.id)
                for match in validMatches {
                    processedEntityIds.insert(match.id)
                }
                groups.append(DuplicateGroup(
                    primary: group.primary,
                    matches: validMatches,
                    confidence: .low
                ))
            }
        }

        // Sort: high confidence first, then alphabetically by primary name
        return groups.sorted { a, b in
            if a.confidence != b.confidence {
                return a.confidence == .high
            }
            return a.primary.originalText.lowercased() < b.primary.originalText.lowercased()
        }
    }

    /// Match result for name comparison
    enum NameMatchResult {
        case noMatch
        case match
        case ambiguousMatch  // Matches but shared across multiple anchors - show as low confidence
    }

    /// Check if a partial name matches components of a full name
    /// Returns .ambiguousMatch for shared names (shown as low confidence for user decision)
    private func isNameMatch(fullName: NameComponents, partial: NameComponents,
                             sharedFirstNames: Set<String>, sharedLastNames: Set<String>) -> NameMatchResult {
        let fullParts = Set(fullName.parts)
        let partialParts = partial.parts


        // Track if this is an ambiguous match (shared name)
        var isAmbiguous = false

        // AMBIGUITY CHECK: Single-word names shared across multiple anchors
        // E.g., "Sean" when both "Sean Lintern" and "Sean Versteegh" exist
        // These are NOT blocked - they're shown as low confidence for user decision
        if partialParts.count == 1 {
            if let partialFirst = partial.firstName?.lowercased(),
               sharedFirstNames.contains(partialFirst) {
                isAmbiguous = true
            }
            if let partialLast = partial.lastName?.lowercased(),
               sharedLastNames.contains(partialLast) {
                isAmbiguous = true
            }
        }

        // Title + last name match (e.g., "Mr Versteegh" matches "Sean Versteegh")
        if partial.hasTitle, let partialLast = partial.lastName, let fullLast = fullName.lastName {
            if partialLast == fullLast {
                if sharedLastNames.contains(partialLast.lowercased()) {
                    return .ambiguousMatch
                }
                return .match
            }
        }

        // First name only match (e.g., "Sean" matches "Sean Versteegh")
        if partialParts.count == 1, let partialFirst = partial.firstName {
            if fullParts.contains(partialFirst) {
                return isAmbiguous ? .ambiguousMatch : .match
            }
        }

        // First + last match (e.g., "Sean Versteegh" matches "Sean Michael Versteegh")
        if partialParts.count == 2,
           let partialFirst = partial.firstName,
           let partialLast = partial.lastName,
           let fullFirst = fullName.firstName,
           let fullLast = fullName.lastName {
            if partialFirst == fullFirst && partialLast == fullLast {
                return .match
            }
        }

        // Any component overlap (single word matches any part)
        if partialParts.count == 1 {
            for part in partialParts {
                if fullParts.contains(part) {
                    return isAmbiguous ? .ambiguousMatch : .match
                }
            }
        }

        return .noMatch
    }

    // Copy button feedback
    @Published var justCopiedAnonymized: Bool = false
    @Published var justCopiedOriginal: Bool = false
    @Published var hasCopiedRedacted: Bool = false

    // MARK: - Multi-Document Support

    @Published var sourceDocuments: [SourceDocument] = []

    var nextDocumentNumber: Int { sourceDocuments.count + 1 }

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

    /// All entities (detected + custom + PII review + BERT NER + XLM-R NER + Deep Scan findings)
    var allEntities: [Entity] {
        guard let result = result else { return customEntities + piiReviewFindings + bertNERFindings + xlmrNERFindings + deepScanFindings }
        let baseEntities = result.entities.filter { !entitiesToRemove.contains($0.id) }
        return baseEntities + customEntities + piiReviewFindings + bertNERFindings + xlmrNERFindings + deepScanFindings
    }

    /// Only active entities (not excluded)
    var activeEntities: [Entity] {
        allEntities.filter { !_excludedIds.contains($0.id) }
    }

    /// Check if an entity is excluded
    func isEntityExcluded(_ entity: Entity) -> Bool {
        _excludedIds.contains(entity.id)
    }

    /// Update nameVariant for an entity matching the given text
    /// Searches all entity sources and updates the first match found
    /// Returns true if an entity was updated
    @discardableResult
    private func updateEntityVariant(matchingText text: String, variant: NameVariant) -> Bool {
        let textLower = text.lowercased()

        // Check result.entities
        if var r = result {
            if let idx = r.entities.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
                r.entities[idx].nameVariant = variant
                result = r
                return true
            }
        }

        // Check customEntities
        if let idx = customEntities.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
            customEntities[idx].nameVariant = variant
            return true
        }

        // Check piiReviewFindings
        if let idx = piiReviewFindings.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
            piiReviewFindings[idx].nameVariant = variant
            return true
        }

        // Check bertNERFindings
        if let idx = bertNERFindings.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
            bertNERFindings[idx].nameVariant = variant
            return true
        }

        // Check xlmrNERFindings
        if let idx = xlmrNERFindings.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
            xlmrNERFindings[idx].nameVariant = variant
            return true
        }

        // Check deepScanFindings
        if let idx = deepScanFindings.firstIndex(where: { $0.originalText.lowercased() == textLower && $0.nameVariant == nil }) {
            deepScanFindings[idx].nameVariant = variant
            return true
        }

        return false
    }

    /// Dynamically generated redacted text based on active entities
    var displayedRedactedText: String {
        // Auto-refresh cache if needed
        if redactedTextNeedsUpdate {
            updateRedactedTextCache()
        }
        return cachedRedactedText
    }

    /// Force update of redacted text cache (call after analysis or entity changes)
    func refreshRedactedTextCache() {
        if redactedTextNeedsUpdate {
            updateRedactedTextCache()
        }
    }

    /// Whether Continue button should be enabled
    var canContinue: Bool {
        let hasCurrentDoc = result != nil && !hasPendingChanges
        let hasSavedDocs = !sourceDocuments.isEmpty
        return hasCurrentDoc || hasSavedDocs
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

            // Update redacted text cache now (not lazily during view render)
            refreshRedactedTextCache()

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
        deepScanFindings.removeAll()
        entitiesToRemove.removeAll()
        isReviewingPII = false
        piiReviewError = nil
        isRunningBertNER = false
        bertNERError = nil
        isRunningXLMRNER = false
        xlmrNERError = nil
        isRunningDeepScan = false
        deepScanError = nil
        engine.clearSession()
        errorMessage = nil
        successMessage = nil

        cachedRedactedText = ""
        redactedTextNeedsUpdate = true

        hasCopiedRedacted = false
        hasPendingChanges = false

        // Clear multi-document state
        sourceDocuments.removeAll()
    }

    // MARK: - Multi-Document Actions

    /// Save current document without clearing state (for Continue to Improve)
    /// State is preserved so user can navigate back and see it
    func saveCurrentDocumentOnly() {
        guard let result = result else { return }

        let doc = SourceDocument(
            documentNumber: nextDocumentNumber,
            name: "Document \(nextDocumentNumber)",
            description: "",
            originalText: result.originalText,
            redactedText: displayedRedactedText,
            entities: activeEntities,
            textInputType: textInputType,
            textInputTypeDescription: textInputTypeDescription
        )
        sourceDocuments.append(doc)
        // Don't clear anything - keep state for back navigation
    }

    /// Save current document and clear for adding another
    /// NOTE: Does NOT clear engine.entityMapping to preserve consistent codes across docs
    func saveCurrentDocumentAndClearForNext() {
        guard let result = result else { return }

        let doc = SourceDocument(
            documentNumber: nextDocumentNumber,
            name: "Document \(nextDocumentNumber)",
            description: "",
            originalText: result.originalText,
            redactedText: displayedRedactedText,
            entities: activeEntities,
            textInputType: textInputType,
            textInputTypeDescription: textInputTypeDescription
        )
        sourceDocuments.append(doc)

        // Clear for next document but preserve entity mapping
        inputText = ""
        self.result = nil
        excludedEntityIds.removeAll()
        _excludedIds.removeAll()
        customEntities.removeAll()
        piiReviewFindings.removeAll()
        bertNERFindings.removeAll()
        xlmrNERFindings.removeAll()
        deepScanFindings.removeAll()
        entitiesToRemove.removeAll()
        cachedRedactedText = ""
        redactedTextNeedsUpdate = true
        hasPendingChanges = false
        hasCopiedRedacted = false
        // NOTE: Do NOT call engine.clearSession() - preserve EntityMapping
    }

    /// Delete a source document by ID
    func deleteSourceDocument(id: UUID) {
        sourceDocuments.removeAll { $0.id == id }
    }

    /// Update description for a source document
    func updateSourceDocumentDescription(id: UUID, description: String) {
        if let idx = sourceDocuments.firstIndex(where: { $0.id == id }) {
            sourceDocuments[idx].description = description
        }
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

    /// Merge alias entity into primary entity
    /// The alias is removed and its positions are consolidated into the primary
    /// Also updates any sibling entities that share the alias's replacement code
    func mergeEntities(alias: Entity, into primary: Entity) {
        guard alias.type == primary.type else { return }

        let aliasCode = alias.replacementCode
        let primaryCode = primary.replacementCode

        // Find all sibling entities that share the alias's replacement code
        // These are connected components that should also be updated
        let siblings = allEntities.filter { $0.replacementCode == aliasCode && $0.id != alias.id }

        // Find and update the primary entity with combined positions from alias
        addPositionsToPrimary(primaryId: primary.id, newPositions: alias.positions)

        // Update the primary entity's code if it changed (e.g., to variant code)
        // This ensures the entity in the list has the correct code for restore
        updateEntityReplacementCode(entityId: primary.id, newCode: primaryCode)

        // Update sibling entities to use the primary's replacement code
        // This preserves the connected components relationship
        for sibling in siblings {
            updateEntityReplacementCode(entityId: sibling.id, newCode: primaryCode)
        }

        // Remove alias from all entity lists (it's now merged into primary)
        removeEntityFromAllLists(entityId: alias.id)

        // Remove alias from excluded set if it was excluded
        _excludedIds.remove(alias.id)
        excludedEntityIds.remove(alias.id)

        // Mark for cache refresh
        redactedTextNeedsUpdate = true

        #if DEBUG
        print("RedactPhaseState.mergeEntities: Merged '\(alias.originalText)' into '\(primary.originalText)' → \(primaryCode)")
        if !siblings.isEmpty {
            print("RedactPhaseState.mergeEntities: Updated \(siblings.count) sibling(s) from \(aliasCode) to \(primaryCode)")
        }
        #endif
    }

    // MARK: - Edit Name Structure

    /// Start editing name structure for an entity
    func startEditingNameStructure(_ entity: Entity) {
        nameStructureEditEntity = entity
        isEditingNameStructure = true
    }

    /// Cancel name structure editing
    func cancelNameStructureEdit() {
        isEditingNameStructure = false
        nameStructureEditEntity = nil
    }

    /// Save the edited name structure
    func saveNameStructure(firstName: String, middleName: String?, lastName: String, title: String?) {
        guard let entity = nameStructureEditEntity else { return }

        // Update the RedactedPerson in EntityMapping
        engine.entityMapping.updatePersonStructure(
            replacementCode: entity.replacementCode,
            firstName: firstName,
            middleName: middleName,
            lastName: lastName,
            title: title
        )

        // Mark cache for refresh since mappings changed
        redactedTextNeedsUpdate = true

        // Close the modal
        isEditingNameStructure = false
        nameStructureEditEntity = nil

        #if DEBUG
        print("RedactPhaseState.saveNameStructure: Updated structure for '\(entity.replacementCode)'")
        #endif
    }

    // MARK: - Variant Selection Modal

    /// Start variant selection for a merge where automatic detection failed
    func startVariantSelection(alias: Entity, primary: Entity) {
        variantSelectionAlias = alias
        variantSelectionPrimary = primary
        isSelectingVariant = true
    }

    /// Cancel variant selection
    func cancelVariantSelection() {
        isSelectingVariant = false
        variantSelectionAlias = nil
        variantSelectionPrimary = nil
    }

    /// Add positions to primary entity across all entity lists
    private func addPositionsToPrimary(primaryId: UUID, newPositions: [[Int]]) {
        if let result = result, let idx = result.entities.firstIndex(where: { $0.id == primaryId }) {
            self.result?.entities[idx].positions.append(contentsOf: newPositions)
        }
        if let idx = customEntities.firstIndex(where: { $0.id == primaryId }) {
            customEntities[idx].positions.append(contentsOf: newPositions)
        }
        if let idx = piiReviewFindings.firstIndex(where: { $0.id == primaryId }) {
            piiReviewFindings[idx].positions.append(contentsOf: newPositions)
        }
        if let idx = bertNERFindings.firstIndex(where: { $0.id == primaryId }) {
            bertNERFindings[idx].positions.append(contentsOf: newPositions)
        }
        if let idx = xlmrNERFindings.firstIndex(where: { $0.id == primaryId }) {
            xlmrNERFindings[idx].positions.append(contentsOf: newPositions)
        }
        if let idx = deepScanFindings.firstIndex(where: { $0.id == primaryId }) {
            deepScanFindings[idx].positions.append(contentsOf: newPositions)
        }
    }

    /// Update an entity's replacement code and recalculate variant across all entity lists
    func updateEntityReplacementCode(entityId: UUID, newCode: String) {
        // Helper to update code and recalculate variant based on new anchor
        func updateEntity(_ entity: inout Entity) {
            entity.replacementCode = newCode
            // Recalculate variant based on matching anchor
            if entity.type.isPerson {
                if let (_, variant) = engine.entityMapping.findVariant(for: entity.originalText) {
                    entity.nameVariant = variant
                } else {
                    entity.nameVariant = nil
                }
            }
        }

        if var r = result, let idx = r.entities.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&r.entities[idx])
            result = r
        }
        if let idx = customEntities.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&customEntities[idx])
        }
        if let idx = piiReviewFindings.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&piiReviewFindings[idx])
        }
        if let idx = bertNERFindings.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&bertNERFindings[idx])
        }
        if let idx = xlmrNERFindings.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&xlmrNERFindings[idx])
        }
        if let idx = deepScanFindings.firstIndex(where: { $0.id == entityId }) {
            updateEntity(&deepScanFindings[idx])
        }
    }

    /// Remove an entity from all entity lists
    private func removeEntityFromAllLists(entityId: UUID) {
        if result != nil {
            self.result?.entities.removeAll { $0.id == entityId }
        }
        customEntities.removeAll { $0.id == entityId }
        piiReviewFindings.removeAll { $0.id == entityId }
        bertNERFindings.removeAll { $0.id == entityId }
        xlmrNERFindings.removeAll { $0.id == entityId }
        deepScanFindings.removeAll { $0.id == entityId }
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

        // Get replacement code from engine (this also registers it for restore)
        let code = engine.entityMapping.getReplacementCode(for: trimmedText, type: type)

        let entity = Entity(
            originalText: trimmedText,
            replacementCode: code,
            type: type,
            positions: positions,
            confidence: 1.0
        )

        customEntities.append(entity)
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

                // Get replacement code from engine (this also registers it for restore)
                let code = engine.entityMapping.getReplacementCode(for: finding.text, type: finding.suggestedType)

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

            // Find all occurrences AND extract name components (first/last names)
            let (positions, componentEntities) = findAllNameOccurrences(of: finding.text, type: finding.suggestedType, in: originalText)
            guard !positions.isEmpty else { continue }

            // Get replacement code from engine (this also registers it for restore)
            let code = engine.entityMapping.getReplacementCode(for: finding.text, type: finding.suggestedType)

            let entity = Entity(
                originalText: finding.text,
                replacementCode: code,
                type: finding.suggestedType,
                positions: positions,
                confidence: finding.confidence
            )

            newEntities.append(entity)

            // Add component entities (first name, last name) with variant labels
            for componentEntity in componentEntities {
                let componentTextLower = componentEntity.originalText.lowercased()

                // Try to update existing entity's variant first
                if let variant = componentEntity.nameVariant {
                    if updateEntityVariant(matchingText: componentEntity.originalText, variant: variant) {
                        continue  // Updated existing entity
                    }
                }

                // Check if component exists in newEntities
                if let idx = newEntities.firstIndex(where: { $0.originalText.lowercased() == componentTextLower }) {
                    // Update variant if existing has none
                    if let variant = componentEntity.nameVariant, newEntities[idx].nameVariant == nil {
                        newEntities[idx].nameVariant = variant
                    }
                    continue
                }

                // Component doesn't exist, add it
                newEntities.append(componentEntity)
            }
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

            // Find all occurrences AND extract name components (first/last names)
            let (positions, componentEntities) = findAllNameOccurrences(of: finding.text, type: finding.suggestedType, in: originalText)
            guard !positions.isEmpty else { continue }

            // Get replacement code from engine (this also registers it for restore)
            let code = engine.entityMapping.getReplacementCode(for: finding.text, type: finding.suggestedType)

            let entity = Entity(
                originalText: finding.text,
                replacementCode: code,
                type: finding.suggestedType,
                positions: positions,
                confidence: finding.confidence
            )

            newEntities.append(entity)

            // Add component entities (first name, last name) with variant labels
            for componentEntity in componentEntities {
                let componentTextLower = componentEntity.originalText.lowercased()

                // Try to update existing entity's variant first
                if let variant = componentEntity.nameVariant {
                    if updateEntityVariant(matchingText: componentEntity.originalText, variant: variant) {
                        continue  // Updated existing entity
                    }
                }

                // Check if component exists in newEntities
                if let idx = newEntities.firstIndex(where: { $0.originalText.lowercased() == componentTextLower }) {
                    // Update variant if existing has none
                    if let variant = componentEntity.nameVariant, newEntities[idx].nameVariant == nil {
                        newEntities[idx].nameVariant = variant
                    }
                    continue
                }

                // Component doesn't exist, add it
                newEntities.append(componentEntity)
            }
        }

        // Merge with existing XLM-R findings, avoiding duplicates
        let existingXLMRTexts = Set(xlmrNERFindings.map { $0.originalText.lowercased() })
        let uniqueNewEntities = newEntities.filter { !existingXLMRTexts.contains($0.originalText.lowercased()) }
        xlmrNERFindings.append(contentsOf: uniqueNewEntities)
    }

    // MARK: - Deep Scan (Apple NER at Lower Confidence)

    /// Run Apple NER with lower confidence (0.75) to catch entities missed by initial scan
    func runDeepScan() async {
        guard let result = result else {
            deepScanError = "Please analyze text first"
            return
        }

        isRunningDeepScan = true
        deepScanError = nil
        successMessage = "Running Deep Scan..."

        let findings = await SwiftNERService.shared.runDeepScan(
            text: result.originalText,
            existingEntities: allEntities
        )

        await MainActor.run {
            let countBefore = deepScanFindings.count
            processDeepScanFindings(findings, originalText: result.originalText)
            let newFindingsCount = deepScanFindings.count - countBefore
            isRunningDeepScan = false

            if newFindingsCount == 0 {
                successMessage = "Deep Scan complete - no additional entities found"
            } else {
                // Auto-exclude deep scan findings (opt-in model: user must check to include)
                for entity in deepScanFindings.suffix(newFindingsCount) {
                    _excludedIds.insert(entity.id)
                }
                excludedEntityIds = _excludedIds

                // Show message explaining opt-in workflow
                deepScanFindingsCount = newFindingsCount
                showDeepScanCompleteMessage = true
                successMessage = "Deep Scan found \(newFindingsCount) additional term(s) - select any to redact"
            }
            autoHideSuccess()
            redactedTextNeedsUpdate = true
        }
    }

    private func processDeepScanFindings(_ findings: [PIIFinding], originalText: String) {
        var newEntities: [Entity] = []

        for finding in findings {
            // Skip if text already exists in current entities
            let alreadyExists = allEntities.contains { $0.originalText.lowercased() == finding.text.lowercased() }
            if alreadyExists { continue }

            // Skip if already added in this batch
            if newEntities.contains(where: { $0.originalText.lowercased() == finding.text.lowercased() }) {
                continue
            }

            // Find all occurrences AND extract name components (first/last names)
            let (positions, componentEntities) = findAllNameOccurrences(of: finding.text, type: finding.suggestedType, in: originalText)
            guard !positions.isEmpty else { continue }

            // Get replacement code from engine (this also registers it for restore)
            let code = engine.entityMapping.getReplacementCode(for: finding.text, type: finding.suggestedType)

            let entity = Entity(
                originalText: finding.text,
                replacementCode: code,
                type: finding.suggestedType,
                positions: positions,
                confidence: finding.confidence
            )

            newEntities.append(entity)

            // Add component entities (first name, last name) with variant labels
            for componentEntity in componentEntities {
                let componentTextLower = componentEntity.originalText.lowercased()

                // Try to update existing entity's variant first
                if let variant = componentEntity.nameVariant {
                    if updateEntityVariant(matchingText: componentEntity.originalText, variant: variant) {
                        continue  // Updated existing entity
                    }
                }

                // Check if component exists in newEntities
                if let idx = newEntities.firstIndex(where: { $0.originalText.lowercased() == componentTextLower }) {
                    // Update variant if existing has none
                    if let variant = componentEntity.nameVariant, newEntities[idx].nameVariant == nil {
                        newEntities[idx].nameVariant = variant
                    }
                    continue
                }

                // Component doesn't exist, add it
                newEntities.append(componentEntity)
            }
        }

        // Merge with existing deep scan findings, avoiding duplicates
        let existingDeepTexts = Set(deepScanFindings.map { $0.originalText.lowercased() })
        let uniqueNewEntities = newEntities.filter { !existingDeepTexts.contains($0.originalText.lowercased()) }
        deepScanFindings.append(contentsOf: uniqueNewEntities)
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
            replacementPositions = []
            redactedTextNeedsUpdate = false
            return
        }

        // Check date redaction setting
        let dateRedactionSetting = UserDefaults.standard.string(forKey: SettingsKeys.dateRedactionLevel) ?? "keepYear"
        let keepYear = dateRedactionSetting == "keepYear"

        // Use NSString for all operations since positions are in UTF-16 (NSRange) coordinates
        let nsText = result.originalText as NSString
        var allReplacements: [(start: Int, end: Int, code: String, entityType: EntityType)] = []

        for entity in activeEntities {
            // Determine code to use (with year for dates if setting enabled)
            var code = entity.replacementCode
            if entity.type == .date && keepYear {
                if let year = extractYearFromDate(entity.originalText) {
                    code = "\(entity.replacementCode) \(year)"
                }
            }

            for position in entity.positions {
                guard position.count >= 2 else { continue }
                let start = position[0]
                let end = position[1]

                // Validate against NSString length (UTF-16), not String.count (grapheme clusters)
                guard start >= 0 && end <= nsText.length && start < end else { continue }
                allReplacements.append((start: start, end: end, code: code, entityType: entity.type))
            }
        }

        // Sort by start position (ascending) to detect overlaps
        allReplacements.sort { $0.start < $1.start }

        // Remove overlapping positions, keeping the longer replacement
        var nonOverlapping: [(start: Int, end: Int, code: String, entityType: EntityType)] = []
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

        // nonOverlapping is sorted ascending by start - perfect for single-pass build
        // Build result in one pass instead of repeated string copies (O(n) vs O(n*m))
        var resultParts: [String] = []
        var newReplacementPositions: [(range: NSRange, entityType: EntityType)] = []
        var currentInputPosition = 0
        var currentOutputPosition = 0

        for replacement in nonOverlapping {
            // Add text before this replacement
            if currentInputPosition < replacement.start {
                let beforeLength = replacement.start - currentInputPosition
                let beforeRange = NSRange(location: currentInputPosition, length: beforeLength)
                resultParts.append(nsText.substring(with: beforeRange))
                currentOutputPosition += beforeLength
            }

            // Add replacement code and track its position in output
            let codeLength = (replacement.code as NSString).length
            let codeRange = NSRange(location: currentOutputPosition, length: codeLength)
            newReplacementPositions.append((range: codeRange, entityType: replacement.entityType))
            resultParts.append(replacement.code)

            currentOutputPosition += codeLength
            currentInputPosition = replacement.end
        }

        // Add remaining text after last replacement
        if currentInputPosition < nsText.length {
            let afterRange = NSRange(location: currentInputPosition, length: nsText.length - currentInputPosition)
            resultParts.append(nsText.substring(with: afterRange))
        }

        cachedRedactedText = resultParts.joined()
        replacementPositions = newReplacementPositions
        redactedTextNeedsUpdate = false
    }

    /// Extract year from a date string (e.g., "March 15, 2024" → "2024")
    private func extractYearFromDate(_ dateString: String) -> String? {
        let yearPattern = "\\b(19|20)\\d{2}\\b"
        guard let regex = try? NSRegularExpression(pattern: yearPattern) else { return nil }
        let range = NSRange(dateString.startIndex..., in: dateString)
        if let match = regex.firstMatch(in: dateString, range: range),
           let matchRange = Range(match.range, in: dateString) {
            return String(dateString[matchRange])
        }
        return nil
    }

    private func findAllOccurrences(of searchText: String, in text: String, includePossessive: Bool = true) -> [[Int]] {
        // Normalize apostrophes for matching (curly ' and straight ')
        let normalizedSearch = searchText
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")
        let normalizedText = text
            .replacingOccurrences(of: "'", with: "'")
            .replacingOccurrences(of: "'", with: "'")

        // Use NSString for UTF-16 positions (consistent with redaction system)
        let nsText = normalizedText as NSString
        var positions: [[Int]] = []

        // Build pattern: match the word, and optionally the possessive form (name + "s")
        // This handles cases like "Sean" also matching "Seans" (possessive without apostrophe)
        let escapedSearch = NSRegularExpression.escapedPattern(for: normalizedSearch)
        let pattern: String
        if includePossessive {
            // Match "Sean" or "Seans" (possessive without apostrophe)
            pattern = "\\b\(escapedSearch)s?\\b"
        } else {
            pattern = "\\b\(escapedSearch)\\b"
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return positions
        }

        let searchRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: normalizedText, options: [], range: searchRange)

        for match in matches {
            // Use NSRange directly for UTF-16 positions
            positions.append([match.range.location, match.range.location + match.range.length])
        }

        return positions
    }

    /// Find all occurrences of entity text AND its name components (first/last names)
    /// Returns main entity positions plus separate entities for name components with variant-aware codes
    private func findAllNameOccurrences(of entityText: String, type: EntityType, in text: String) -> (mainPositions: [[Int]], componentEntities: [Entity]) {
        // Find main entity occurrences
        let mainPositions = findAllOccurrences(of: entityText, in: text)

        var componentEntities: [Entity] = []

        // Only extract components for person names
        guard type.isPerson else { return (mainPositions, []) }

        // Strip title and get name parts
        let stripped = RedactedPerson.stripTitle(entityText)
        let words = stripped.split(separator: " ").map { String($0) }
        guard words.count >= 2 else { return (mainPositions, []) }

        // Register this as a person anchor to enable variant tracking
        guard let person = engine.entityMapping.registerPersonAnchor(fullName: entityText, type: type) else {
            // Fallback to old behavior if registration fails
            let parentCode = engine.entityMapping.getReplacementCode(for: entityText, type: type)
            return createComponentEntitiesLegacy(entityText: entityText, type: type, text: text, parentCode: parentCode, mainPositions: mainPositions)
        }

        // Extract first name with variant code
        let firstName = words[0]
        if firstName.count >= 3 {
            let positions = findAllOccurrences(of: firstName, in: text)
            if !positions.isEmpty {
                componentEntities.append(Entity(
                    originalText: firstName,
                    replacementCode: person.placeholder(for: .first),
                    type: type,
                    positions: positions,
                    confidence: 0.9,
                    nameVariant: .first
                ))
            }
        }

        // Extract last name with variant code
        let lastName = words.last!
        if lastName.count >= 3 && lastName != firstName {
            let positions = findAllOccurrences(of: lastName, in: text)
            if !positions.isEmpty {
                componentEntities.append(Entity(
                    originalText: lastName,
                    replacementCode: person.placeholder(for: .last),
                    type: type,
                    positions: positions,
                    confidence: 0.9,
                    nameVariant: .last
                ))
            }
        }

        // Extract middle name(s) if present
        if words.count >= 3 {
            let middleNames = words[1..<words.count-1].joined(separator: " ")
            if middleNames.count >= 2 {
                let positions = findAllOccurrences(of: middleNames, in: text)
                if !positions.isEmpty {
                    componentEntities.append(Entity(
                        originalText: middleNames,
                        replacementCode: person.placeholder(for: .middle),
                        type: type,
                        positions: positions,
                        confidence: 0.9,
                        nameVariant: .middle
                    ))
                }
            }
        }

        // Check for formal address (Title + Last) in text
        if let title = RedactedPerson.extractTitle(entityText) {
            let formalForm = "\(title) \(lastName)"
            let positions = findAllOccurrences(of: formalForm, in: text)
            if !positions.isEmpty {
                componentEntities.append(Entity(
                    originalText: formalForm,
                    replacementCode: person.placeholder(for: .formal),
                    type: type,
                    positions: positions,
                    confidence: 0.95,
                    nameVariant: .formal
                ))
            }
        }

        return (mainPositions, componentEntities)
    }

    /// Legacy fallback for component entity creation (no variant support)
    private func createComponentEntitiesLegacy(entityText: String, type: EntityType, text: String, parentCode: String, mainPositions: [[Int]]) -> (mainPositions: [[Int]], componentEntities: [Entity]) {
        var componentEntities: [Entity] = []
        let words = entityText.split(separator: " ").map { String($0) }

        // Extract first name
        if let firstName = words.first, firstName.count >= 3 {
            let positions = findAllOccurrences(of: firstName, in: text)
            if !positions.isEmpty {
                componentEntities.append(Entity(
                    originalText: firstName,
                    replacementCode: parentCode,
                    type: type,
                    positions: positions,
                    confidence: 0.9
                ))
            }
        }

        // Extract last name
        if let lastName = words.last, lastName.count >= 3 && words.count >= 2 && lastName != words.first {
            let positions = findAllOccurrences(of: lastName, in: text)
            if !positions.isEmpty {
                componentEntities.append(Entity(
                    originalText: lastName,
                    replacementCode: parentCode,
                    type: type,
                    positions: positions,
                    confidence: 0.9
                ))
            }
        }

        return (mainPositions, componentEntities)
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

    /// Force cache invalidation and refresh (called when entities change externally)
    func invalidateCache() {
        redactedTextNeedsUpdate = true
        refreshRedactedTextCache()
    }
}
