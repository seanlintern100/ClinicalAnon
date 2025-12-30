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

    let redactState: RedactPhaseState
    let improveState: ImprovePhaseState
    let restoreState: RestorePhaseState
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
            self?.redactState.displayedRedactedText ?? ""
        }

        restoreState.getAIOutput = { [weak self] in
            self?.improveState.aiOutput ?? ""
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

    // MARK: - Forwarded Properties (Redact Phase)

    var inputText: String {
        get { redactState.inputText }
        set { redactState.inputText = newValue }
    }

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

    var cachedRedactedText: String { redactState.cachedRedactedText }

    var showingAddCustom: Bool {
        get { redactState.showingAddCustom }
        set { redactState.showingAddCustom = newValue }
    }

    var prefilledText: String? {
        get { redactState.prefilledText }
        set { redactState.prefilledText = newValue }
    }

    var justCopiedAnonymized: Bool { redactState.justCopiedAnonymized }
    var justCopiedOriginal: Bool { redactState.justCopiedOriginal }
    var hasCopiedRedacted: Bool { redactState.hasCopiedRedacted }
    var hasPendingChanges: Bool { redactState.hasPendingChanges }

    // MARK: - Forwarded Properties (Improve Phase)

    var selectedDocumentType: DocumentType? {
        get { improveState.selectedDocumentType }
        set { improveState.selectedDocumentType = newValue }
    }

    var sliderSettings: SliderSettings {
        get { improveState.sliderSettings }
        set { improveState.sliderSettings = newValue }
    }

    var customInstructions: String {
        get { improveState.customInstructions }
        set { improveState.customInstructions = newValue }
    }

    var aiOutput: String { improveState.aiOutput }
    var isAIProcessing: Bool { improveState.isAIProcessing }
    var aiError: String? { improveState.aiError }
    var isInRefinementMode: Bool { improveState.isInRefinementMode }

    var refinementInput: String {
        get { improveState.refinementInput }
        set { improveState.refinementInput = newValue }
    }

    var chatHistory: [(role: String, content: String)] { improveState.chatHistory }
    var streamingDestination: StreamingDestination { improveState.streamingDestination }
    var currentDocument: String { improveState.currentDocument }
    var previousDocument: String { improveState.previousDocument }
    var changedLineIndices: Set<Int> { improveState.changedLineIndices }

    var showPromptEditor: Bool {
        get { improveState.showPromptEditor }
        set { improveState.showPromptEditor = newValue }
    }

    var showAddCustomCategory: Bool {
        get { improveState.showAddCustomCategory }
        set { improveState.showAddCustomCategory = newValue }
    }

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
            currentPhase = previous
        }
    }

    func continueToNextPhase() {
        switch currentPhase {
        case .redact:
            guard canContinueFromRedact else { return }
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
        await redactState.analyze()
    }

    func clearAll() {
        redactState.clearAll()
        improveState.clearAll()
        restoreState.clearAll()
        cacheManager.clearAll()
        currentPhase = .redact
    }

    func toggleEntity(_ entity: Entity) {
        redactState.toggleEntity(entity)
    }

    func applyChanges() {
        redactState.applyChanges()
    }

    func openAddCustomEntity(withText text: String? = nil) {
        redactState.openAddCustomEntity(withText: text)
    }

    func addCustomEntity(text: String, type: EntityType) {
        redactState.addCustomEntity(text: text, type: type)
    }

    func runLocalPIIReview() async {
        await redactState.runLocalPIIReview()
    }

    // MARK: - Improve Phase Actions

    func processWithAI() {
        improveState.processWithAI()
    }

    func sendRefinement() {
        improveState.sendRefinement()
    }

    func exitRefinementMode() {
        improveState.exitRefinementMode()
    }

    func regenerateAIOutput() {
        improveState.regenerateAIOutput()
    }

    func startOverAI() {
        improveState.startOver()
    }

    func cancelAIRequest() {
        improveState.cancelAIRequest()
    }

    func editPrompt(for docType: DocumentType) {
        improveState.editPrompt(for: docType)
    }

    func openAddCustomCategory() {
        improveState.openAddCustomCategory()
    }

    // MARK: - Restore Phase Actions

    func restoreNamesFromAIOutput() {
        restoreState.restoreNamesFromAIOutput()
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
            restoredText: finalRestoredText.isEmpty ? nil : finalRestoredText
        )
    }
}
