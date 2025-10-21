//
//  AnonymizationView.swift
//  ClinicalAnon
//
//  Purpose: Main anonymization interface
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Anonymization View

/// Main view for clinical text anonymization
struct AnonymizationView: View {

    // MARK: - Properties

    @StateObject private var viewModel: AnonymizationViewModel
    private let setupManager: SetupManager

    // MARK: - Initialization

    init(ollamaService: OllamaServiceProtocol, setupManager: SetupManager) {
        let engine = AnonymizationEngine(ollamaService: ollamaService)
        self.setupManager = setupManager
        _viewModel = StateObject(wrappedValue: AnonymizationViewModel(engine: engine, setupManager: setupManager))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Compact Header
            CompactHeaderView(setupManager: setupManager, viewModel: viewModel)

            Divider()

            // Main three-pane content
            HSplitView {
                // LEFT PANE: Original Text
                VStack(spacing: 0) {
                    // Title bar with Analyze button
                    HStack {
                        Text("Original Text")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Spacer()

                        if !viewModel.inputText.isEmpty {
                            Text("\(viewModel.inputText.split(separator: " ").count) words")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.trailing, DesignSystem.Spacing.small)
                        }

                        // Analyze button - always present (disabled when empty)
                        Button(action: { Task { await viewModel.analyze() } }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                if viewModel.isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .frame(width: 14, height: 14)
                                }
                                Text(viewModel.isProcessing ? "Analyzing..." : "Analyze")
                                    .frame(minWidth: 70)
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(viewModel.inputText.isEmpty || viewModel.isProcessing)
                    }
                    .frame(height: 52)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    Divider()

                    // Text editor or highlighted text - fills all available space
                    if let result = viewModel.result {
                        // Show highlighted version when we have results
                        ScrollView {
                            Text(attributedOriginalText(viewModel.inputText, result: result))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("original-highlighted-\(result.id)")
                    } else {
                        // Show editable TextEditor when no results
                        ZStack(alignment: .topLeading) {
                            if viewModel.inputText.isEmpty {
                                Text("Paste clinical text here to anonymize...")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                                    .padding(DesignSystem.Spacing.medium)
                            }

                            TextEditor(text: $viewModel.inputText)
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("original-editor")
                    }
                }
                .background(DesignSystem.Colors.surface)
                .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                // MIDDLE PANE: Redacted Text
                VStack(spacing: 0) {
                    // Title bar with Copy button
                    HStack {
                        Text("Redacted Text")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Spacer()

                        if let result = viewModel.result {
                            Text("\(result.entityCount) \(result.entityCount == 1 ? "entity" : "entities")")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                                .padding(.trailing, DesignSystem.Spacing.small)

                            Button(action: { viewModel.copyAnonymizedText() }) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "doc.on.doc")
                                        .frame(width: 14, height: 14)
                                    Text("Copy")
                                        .frame(minWidth: 70)
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .frame(height: 52)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    Divider()

                    // Redacted text display - fills all available space
                    if let result = viewModel.result {
                        ScrollView {
                            Text(attributedRedactedText(result))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("redacted-\(result.id)")
                    } else {
                        VStack(spacing: DesignSystem.Spacing.medium) {
                            Spacer()

                            Image(systemName: "lock.fill")
                                .font(.system(size: 48))
                                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

                            Text("Redacted text will appear here")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textSecondary)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("redacted-placeholder")
                    }
                }
                .background(DesignSystem.Colors.surface)
                .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                // RIGHT PANE: Restored Text
                VStack(spacing: 0) {
                    // Title bar with Restore and Copy buttons
                    HStack {
                        Text("Restored Text")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Spacer()

                        if !viewModel.restoredText.isEmpty {
                            Button(action: { viewModel.copyRestoredText() }) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "doc.on.doc")
                                        .frame(width: 14, height: 14)
                                    Text("Copy")
                                        .frame(minWidth: 70)
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else if !viewModel.aiImprovedText.isEmpty {
                            Button(action: { viewModel.restoreNames() }) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    Image(systemName: "lock.open.fill")
                                        .frame(width: 14, height: 14)
                                    Text("Restore Names")
                                        .frame(minWidth: 70)
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(viewModel.result == nil)
                        }
                    }
                    .frame(height: 52)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.xs)

                    Divider()

                    // AI-improved text input OR restored result
                    if viewModel.restoredText.isEmpty {
                        // Input for AI-improved text
                        ZStack(alignment: .topLeading) {
                            if viewModel.aiImprovedText.isEmpty {
                                Text("Paste AI-improved text with placeholders here...")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                                    .padding(DesignSystem.Spacing.medium)
                            }

                            TextEditor(text: $viewModel.aiImprovedText)
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("restored-editor")
                    } else {
                        // Show restored text with highlighting
                        ScrollView {
                            if let result = viewModel.result {
                                Text(attributedRestoredText(viewModel.restoredText, result: result))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DesignSystem.Spacing.medium)
                            } else {
                                Text(viewModel.restoredText)
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DesignSystem.Spacing.medium)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("restored-highlighted-\(viewModel.restoredText.hashValue)")
                    }
                }
                .background(DesignSystem.Colors.surface)
                .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Bottom status bar
            HStack(spacing: DesignSystem.Spacing.medium) {
                Button(action: { viewModel.clearAll() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "trash")
                        Text("Clear All")
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.inputText.isEmpty && viewModel.result == nil && viewModel.aiImprovedText.isEmpty)

                Spacer()

                // Status indicator
                if viewModel.isProcessing {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        ProgressView()
                            .scaleEffect(0.7)

                        Text(viewModel.statusMessage.isEmpty ? "Processing..." : viewModel.statusMessage)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        if viewModel.estimatedSeconds > 0 {
                            Text("~\(viewModel.estimatedSeconds)s")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                } else if viewModel.result != nil {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.success)
                        Text("Complete")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                } else {
                    Text("Ready")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.background)

            // Error/Success banners
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) {
                    viewModel.dismissError()
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.bottom, DesignSystem.Spacing.small)
            }

            if let success = viewModel.successMessage {
                SuccessBanner(message: success) {
                    viewModel.dismissSuccess()
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.bottom, DesignSystem.Spacing.small)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(DesignSystem.Colors.background)
    }

    // Helper to create attributed text with highlights for redacted text
    private func attributedRedactedText(_ result: AnonymizationResult) -> AttributedString {
        var attributedString = AttributedString(result.anonymizedText)

        // Apply default font - smaller size for consistency
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight redacted entities with type-specific colors
        for entity in result.entities {
            // Find all occurrences of the replacement code in the attributed string
            let code = entity.replacementCode
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                // Search in the remaining portion of the attributed string
                let searchRange = searchStart..<attributedString.endIndex

                // Find the replacement code
                if let range = attributedString[searchRange].range(of: code) {
                    // Apply type-specific highlighting
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

                    // Move search start forward past this match
                    searchStart = range.upperBound
                } else {
                    // No more matches found
                    break
                }
            }
        }

        return attributedString
    }

    // Helper to create attributed text with highlights for original text
    private func attributedOriginalText(_ inputText: String, result: AnonymizationResult) -> AttributedString {
        var attributedString = AttributedString(inputText)

        // Apply default font
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight original entities with type-specific colors
        for entity in result.entities {
            let originalText = entity.originalText
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex

                // Find the original entity text (case-insensitive)
                if let range = attributedString[searchRange].range(of: originalText, options: [.caseInsensitive]) {
                    // Apply type-specific highlighting
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

    // Helper to create attributed text with highlights for restored text
    private func attributedRestoredText(_ restoredText: String, result: AnonymizationResult) -> AttributedString {
        var attributedString = AttributedString(restoredText)

        // Apply default font
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight restored entities with type-specific colors
        for entity in result.entities {
            let originalText = entity.originalText
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex

                // Find the restored entity text (case-insensitive)
                if let range = attributedString[searchRange].range(of: originalText, options: [.caseInsensitive]) {
                    // Apply type-specific highlighting
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
}

// MARK: - Compact Header View

struct CompactHeaderView: View {
    let setupManager: SetupManager
    @ObservedObject var viewModel: AnonymizationViewModel

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Text("Redactor")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            Spacer()

            // Detection mode picker
            DetectionModePicker(engine: viewModel.engine)

            // Model info
            ModelBadge(setupManager: setupManager)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Model Picker

struct ModelBadge: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        Menu {
            ForEach(installedModels) { model in
                Button(action: {
                    setupManager.selectedModel = model.name
                }) {
                    HStack {
                        Text(model.displayName)
                        if setupManager.selectedModel == model.name {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if !installedModels.isEmpty {
                Divider()
            }

            Button("Manage Models...") {
                setupManager.state = .selectingModel
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "cpu")
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                    .font(.system(size: 11))

                Text(modelDisplayName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Image(systemName: "chevron.down")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .font(.system(size: 9))
            }
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .menuStyle(.borderlessButton)
    }

    private var installedModels: [ModelInfo] {
        let installed = setupManager.getInstalledModels()
        return setupManager.availableModels.filter { installed.contains($0.name) }
    }

    private var modelDisplayName: String {
        setupManager.availableModels.first(where: { $0.name == setupManager.selectedModel })?.displayName ?? "Model"
    }
}


// MARK: - View Model

@MainActor
class AnonymizationViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var inputText: String = ""
    @Published var result: AnonymizationResult?
    @Published var isProcessing: Bool = false
    @Published var estimatedSeconds: Int = 0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // Restore functionality
    @Published var aiImprovedText: String = ""
    @Published var restoredText: String = ""

    // MARK: - Properties (accessible for UI)

    let engine: AnonymizationEngine
    let setupManager: SetupManager

    // Detection mode from engine (forwarding)
    var detectionMode: DetectionMode {
        get { engine.detectionMode }
        set { engine.detectionMode = newValue }
    }

    // MARK: - Initialization

    init(engine: AnonymizationEngine, setupManager: SetupManager) {
        self.engine = engine
        self.setupManager = setupManager
    }

    // Update UI from engine properties
    private func updateFromEngine() {
        isProcessing = engine.isProcessing
        estimatedSeconds = engine.estimatedSeconds
        statusMessage = engine.statusMessage
    }

    // MARK: - Actions

    func analyze() async {
        guard !inputText.isEmpty else { return }

        // Update model name from setup manager before processing
        engine.updateModelName(setupManager.selectedModel)

        // Dismiss previous messages
        errorMessage = nil
        successMessage = nil

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

            updateTask.cancel()
            updateFromEngine()

            successMessage = "Anonymization complete! Found \(result?.entityCount ?? 0) entities."

            // Auto-dismiss success after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                successMessage = nil
            }
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
        aiImprovedText = ""
        restoredText = ""
        engine.clearSession()
        errorMessage = nil
        successMessage = nil
    }

    func clearInputText() {
        inputText = ""
    }

    func copyInputText() {
        copyToClipboard(inputText)
        successMessage = "Original text copied to clipboard"
        autoHideSuccess()
    }

    func copyAnonymizedText() {
        guard let text = result?.anonymizedText else { return }
        copyToClipboard(text)
        successMessage = "Anonymized text copied to clipboard"
        autoHideSuccess()
    }

    func restoreNames() {
        guard !aiImprovedText.isEmpty else {
            errorMessage = "Please paste AI-improved text first"
            return
        }

        guard result != nil else {
            errorMessage = "Please analyze text first to create mapping"
            return
        }

        print("🔄 Restoring names from AI-improved text...")

        // Use TextReidentifier to restore original names
        let reidentifier = TextReidentifier()
        restoredText = reidentifier.restore(text: aiImprovedText, using: engine.entityMapping)

        successMessage = "Names restored successfully!"
        autoHideSuccess()

        print("✅ Restoration complete")
    }

    func copyRestoredText() {
        guard !restoredText.isEmpty else { return }
        copyToClipboard(restoredText)
        successMessage = "Restored text copied to clipboard"
        autoHideSuccess()
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissSuccess() {
        successMessage = nil
    }

    // MARK: - Private Methods

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func autoHideSuccess() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        }
    }
}

// MARK: - Text Reidentifier

/// Service that reverses anonymization by replacing placeholders with original text
class TextReidentifier {

    /// Replace all placeholders with original text
    @MainActor
    func restore(text: String, using mapping: EntityMapping) -> String {
        var result = text

        // Get all mappings from EntityMapping
        let allMappings = mapping.allMappings

        // Create reverse mapping: [PERSON_A] → "John"
        let reverseMappings = allMappings.map {
            (placeholder: $0.replacement, original: $0.original)
        }

        // Sort by placeholder length (longest first to avoid partial replacements)
        let sorted = reverseMappings.sorted { $0.placeholder.count > $1.placeholder.count }

        print("🔄 TextReidentifier: Restoring \(sorted.count) placeholders")

        // Replace each placeholder with original text
        for mapping in sorted {
            let occurrences = result.components(separatedBy: mapping.placeholder).count - 1
            if occurrences > 0 {
                result = result.replacingOccurrences(
                    of: mapping.placeholder,
                    with: mapping.original
                )
                print("  ✓ Replaced \(mapping.placeholder) → '\(mapping.original)' (\(occurrences) times)")
            }
        }

        return result
    }
}

// MARK: - Detection Mode Picker

struct DetectionModePicker: View {
    @ObservedObject var engine: AnonymizationEngine

    var body: some View {
        Menu {
            ForEach(DetectionMode.allCases) { mode in
                Button(action: {
                    engine.detectionMode = mode
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(DesignSystem.Typography.caption)
                            Text(mode.description)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        if engine.detectionMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: modeIcon(engine.detectionMode))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                    .font(.system(size: 12))

                Text(engine.detectionMode.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Image(systemName: "chevron.down")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, 4)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
        .menuStyle(.borderlessButton)
    }

    private func modeIcon(_ mode: DetectionMode) -> String {
        switch mode {
        case .aiModel:
            return "brain"
        case .patterns:
            return "bolt.fill"
        case .hybrid:
            return "star.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AnonymizationView_Previews: PreviewProvider {
    static var previews: some View {
        AnonymizationView(
            ollamaService: OllamaService(mockMode: true),
            setupManager: SetupManager.preview
        )
        .frame(width: 1200, height: 700)
    }
}
#endif
