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
    }

    func dismissError() {
        errorMessage = nil
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
