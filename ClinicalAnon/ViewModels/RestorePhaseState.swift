//
//  RestorePhaseState.swift
//  Redactor
//
//  Purpose: Manages state for the Restore phase of the workflow
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Restore Phase State

/// State management for the Restore (re-identification) phase
@MainActor
class RestorePhaseState: ObservableObject {

    // MARK: - Output

    @Published var finalRestoredText: String = ""
    @Published var hasRestoredText: Bool = false

    // MARK: - Copy Feedback

    @Published var justCopiedRestored: Bool = false

    // MARK: - Error State

    @Published var errorMessage: String?

    // MARK: - Edit Replacement State

    @Published var showEditReplacementModal: Bool = false
    @Published var entityBeingEdited: Entity?
    @Published var editedReplacementText: String = ""

    /// Custom overrides: [replacementCode: customText]
    /// When user edits a replacement, store the custom text here
    @Published var replacementOverrides: [String: String] = [:]

    // MARK: - Services

    private let reidentifier = TextReidentifier()

    // Callbacks for getting data from other phases
    var getAIOutput: (() -> String)?
    var getEntityMapping: (() -> EntityMapping?)?

    // Cache manager for highlight caching
    weak var cacheManager: HighlightCacheManager?

    // MARK: - Actions

    /// Restore names from AI output
    func restoreNamesFromAIOutput() {
        guard let getOutput = getAIOutput, let getMapping = getEntityMapping else {
            errorMessage = "Restore phase not properly configured"
            return
        }

        let aiOutput = getOutput()
        guard !aiOutput.isEmpty else {
            errorMessage = "No AI output to restore"
            return
        }

        guard let mapping = getMapping() else {
            errorMessage = "No entity mapping available"
            return
        }

        finalRestoredText = reidentifier.restore(text: aiOutput, using: mapping)
        hasRestoredText = true

        // Note: Cache rebuild is now handled by WorkflowViewModel.restoreNamesFromAIOutput()
    }

    /// Copy restored text to clipboard with formatting
    func copyRestoredText() {
        guard !finalRestoredText.isEmpty else { return }
        copyFormattedToClipboard(finalRestoredText)
        justCopiedRestored = true
        autoResetCopyState()
    }

    /// Reset all state
    func clearAll() {
        finalRestoredText = ""
        hasRestoredText = false
        justCopiedRestored = false
        errorMessage = nil
        replacementOverrides.removeAll()
        showEditReplacementModal = false
        entityBeingEdited = nil
        editedReplacementText = ""
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Edit Replacement Actions

    /// Start editing a replacement - opens modal with current text
    func startEditingReplacement(_ entity: Entity) {
        entityBeingEdited = entity
        // Use override if exists, otherwise use original text
        editedReplacementText = replacementOverrides[entity.replacementCode] ?? entity.originalText
        showEditReplacementModal = true
    }

    /// Apply the edited replacement text
    func applyReplacementEdit() {
        guard let entity = entityBeingEdited else { return }

        // Store the override
        replacementOverrides[entity.replacementCode] = editedReplacementText

        // Rebuild restored text with new override
        rebuildRestoredText()

        // Close modal
        showEditReplacementModal = false
        entityBeingEdited = nil
    }

    /// Cancel editing - close modal without saving
    func cancelReplacementEdit() {
        showEditReplacementModal = false
        entityBeingEdited = nil
        editedReplacementText = ""
    }

    /// Rebuild restored text using current overrides
    func rebuildRestoredText() {
        guard let getOutput = getAIOutput, let getMapping = getEntityMapping else { return }

        let aiOutput = getOutput()
        guard !aiOutput.isEmpty else { return }

        guard let mapping = getMapping() else { return }

        // Restore with overrides
        finalRestoredText = reidentifier.restoreWithOverrides(
            text: aiOutput,
            using: mapping,
            overrides: replacementOverrides
        )

        // Rebuild cache
        cacheManager?.rebuildRestoredCache(restoredText: finalRestoredText)
    }

    // MARK: - Private Methods

    private func copyFormattedToClipboard(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtfData = MarkdownParser.parseToRTFData(markdown) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        pasteboard.setString(markdown, forType: .string)
    }

    private func autoResetCopyState() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            justCopiedRestored = false
        }
    }
}
