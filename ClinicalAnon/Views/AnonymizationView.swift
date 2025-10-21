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

            // Main content with sidebar
            HSplitView {
                // Entity Management Sidebar (only show after analysis)
                if viewModel.result != nil {
                    EntityManagementSidebar(viewModel: viewModel)
                }

                // Three-pane content area
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
                        // Show highlighted version with double-click support when we have results
                        InteractiveTextView(
                            attributedText: attributedOriginalText(viewModel.inputText, result: result),
                            onDoubleClick: { word in
                                viewModel.openAddCustomEntity(withText: word)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("original-highlighted-\(result.id)-\(viewModel.excludedEntityIds.count)-\(viewModel.customEntities.count)")
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
                            Text(attributedRedactedText())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("redacted-\(result.id)-\(viewModel.excludedEntityIds.count)-\(viewModel.customEntities.count)")
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
    private func attributedRedactedText() -> AttributedString {
        // Use dynamically generated redacted text based on active entities
        var attributedString = AttributedString(viewModel.displayedRedactedText)

        // Apply default font - smaller size for consistency
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight active (non-excluded) entities with type-specific colors
        for entity in viewModel.activeEntities {
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

        // Highlight original entities with type-specific colors (or gray if excluded)
        for entity in viewModel.allEntities {
            let originalText = entity.originalText
            var searchStart = attributedString.startIndex

            // Check if entity is excluded (restored)
            let isExcluded = viewModel.excludedEntityIds.contains(entity.id)

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex

                // Find the original entity text (case-insensitive)
                if let range = attributedString[searchRange].range(of: originalText, options: [.caseInsensitive]) {
                    // Apply gray highlighting if excluded, type-specific color if active
                    if isExcluded {
                        attributedString[range].backgroundColor = NSColor.gray.withAlphaComponent(0.3)
                        attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textSecondary)
                    } else {
                        attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                        attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                    }

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

    // Entity management
    @Published var excludedEntityIds: Set<UUID> = []
    @Published var customEntities: [Entity] = []

    // Add custom entity dialog state
    @Published var showingAddCustom: Bool = false
    @Published var prefilledText: String? = nil

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

    // MARK: - Entity Management Computed Properties

    /// All entities (detected + custom)
    var allEntities: [Entity] {
        guard let result = result else { return customEntities }
        return result.entities + customEntities
    }

    /// Only active entities (not excluded)
    var activeEntities: [Entity] {
        allEntities.filter { !excludedEntityIds.contains($0.id) }
    }

    /// Dynamically generated redacted text based on active entities
    var displayedRedactedText: String {
        guard let result = result else { return "" }

        do {
            // Start with original text
            var text = result.originalText

            // Flatten all positions from all entities into a single list
            // Each item is (start, end, replacementCode)
            var allReplacements: [(start: Int, end: Int, code: String)] = []

            for entity in activeEntities {
                for position in entity.positions {
                    guard position.count >= 2 else { continue }
                    let start = position[0]
                    let end = position[1]

                    // Validate positions are within bounds
                    guard start >= 0 && end <= text.count && start < end else {
                        print("⚠️ Invalid position [\(start), \(end)] for text length \(text.count)")
                        continue
                    }

                    allReplacements.append((start: start, end: end, code: entity.replacementCode))
                }
            }

            // Sort all replacements by position (descending - last to first)
            // This preserves string indices as we replace from end to start
            allReplacements.sort { $0.start > $1.start }

            // Replace each position from last to first
            for replacement in allReplacements {
                guard replacement.start < text.count && replacement.end <= text.count else {
                    print("⚠️ Skipping out-of-bounds replacement at [\(replacement.start), \(replacement.end)]")
                    continue
                }

                let start = text.index(text.startIndex, offsetBy: replacement.start)
                let end = text.index(text.startIndex, offsetBy: replacement.end)

                // Validate string indices before replacement
                guard start < text.endIndex && end <= text.endIndex && start < end else {
                    print("⚠️ Invalid string indices for replacement")
                    continue
                }

                text.replaceSubrange(start..<end, with: replacement.code)
            }

            return text
        } catch {
            print("❌ Error generating redacted text: \(error)")
            return result.anonymizedText // Fallback to original result
        }
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
        excludedEntityIds.removeAll()
        customEntities.removeAll()
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
        guard result != nil else { return }
        let text = displayedRedactedText
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

    // MARK: - Entity Management Actions

    /// Toggle an entity on/off (excluded entities are restored in redacted text)
    func toggleEntity(_ entity: Entity) {
        if excludedEntityIds.contains(entity.id) {
            excludedEntityIds.remove(entity.id)
        } else {
            excludedEntityIds.insert(entity.id)
        }
    }

    /// Add a custom redaction for text that wasn't automatically detected
    /// Open the Add Custom Entity dialog with optional pre-filled text
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

        // Find all occurrences in original text
        let positions = findAllOccurrences(of: trimmedText, in: result.originalText)
        guard !positions.isEmpty else {
            errorMessage = "Text '\(trimmedText)' not found in original document"
            return
        }

        // Get next code for this type (considering both detected and custom entities)
        let existingCount = allEntities.filter { $0.type == type }.count
        let code = type.replacementCode(for: existingCount)

        // Create entity
        let entity = Entity(
            originalText: trimmedText,
            replacementCode: code,
            type: type,
            positions: positions,
            confidence: 1.0
        )

        customEntities.append(entity)

        // Add to mapping
        _ = engine.entityMapping.getReplacementCode(for: trimmedText, type: type)

        successMessage = "Added custom redaction: \(code) (\(positions.count) occurrences)"
        autoHideSuccess()
    }

    // MARK: - Private Methods

    /// Find all occurrences of text in a string (case-insensitive)
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
    }

    private func autoHideSuccess() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        }
    }
}

// MARK: - Entity Management Sidebar

struct EntityManagementSidebar: View {
    @ObservedObject var viewModel: AnonymizationViewModel
    @State private var isCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack(spacing: DesignSystem.Spacing.small) {
                Button(action: { withAnimation { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")

                if !isCollapsed {
                    Text("Entities (\(viewModel.allEntities.count))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Button(action: { viewModel.openAddCustomEntity() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                    }
                    .buttonStyle(.plain)
                    .help("Add custom redaction")
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)

            if !isCollapsed {
                Divider()

                // Entity list
                if viewModel.allEntities.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.small) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                        Text("No entities detected")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(viewModel.allEntities) { entity in
                                EntitySidebarRow(
                                    entity: entity,
                                    isActive: !viewModel.excludedEntityIds.contains(entity.id),
                                    onToggle: { viewModel.toggleEntity(entity) }
                                )
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.small)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                    }
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .frame(
            minWidth: isCollapsed ? 40 : 220,
            idealWidth: isCollapsed ? 40 : 240,
            maxWidth: isCollapsed ? 40 : 400
        )
        .sheet(isPresented: $viewModel.showingAddCustom) {
            AddCustomEntityView(viewModel: viewModel, isPresented: $viewModel.showingAddCustom, initialText: viewModel.prefilledText)
        }
    }
}

struct EntitySidebarRow: View {
    let entity: Entity
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // Checkbox column
            Toggle("", isOn: Binding(
                get: { isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            // Original text column (flexible width)
            Text(entity.originalText)
                .font(.system(size: 12))
                .foregroundColor(isActive ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow column (fixed width, centered)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                .frame(width: 20)

            // Replacement code column (fixed width, left aligned)
            Text(entity.replacementCode)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .background(isActive ? Color.clear : DesignSystem.Colors.surface.opacity(0.5))
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Entity Management Panel (Legacy - kept for reference)

struct EntityManagementPanel: View {
    @ObservedObject var viewModel: AnonymizationViewModel
    @State private var isExpanded = true
    @State private var showingAddCustom = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)

                Text("Detected Entities (\(viewModel.allEntities.count))")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                if viewModel.result != nil {
                    Button("+ Add Custom") {
                        showingAddCustom = true
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 44)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.surface)

            if isExpanded && !viewModel.allEntities.isEmpty {
                Divider()

                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(viewModel.allEntities) { entity in
                            EntityManagementRow(
                                entity: entity,
                                isActive: !viewModel.excludedEntityIds.contains(entity.id),
                                onToggle: { viewModel.toggleEntity(entity) }
                            )
                        }
                    }
                    .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxHeight: 200)
                .background(DesignSystem.Colors.background)
            }
        }
        .sheet(isPresented: $viewModel.showingAddCustom) {
            AddCustomEntityView(viewModel: viewModel, isPresented: $viewModel.showingAddCustom, initialText: viewModel.prefilledText)
        }
    }
}

struct EntityManagementRow: View {
    let entity: Entity
    let isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Toggle("", isOn: Binding(
                get: { isActive },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Text(entity.originalText)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(minWidth: 150, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .font(.system(size: 10))

            Text(entity.replacementCode)
                .font(DesignSystem.Typography.bodyBold)
                .foregroundColor(isActive ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)

            Spacer()

            Text(entity.type.displayName)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, 2)
                .background(entity.type.highlightColor.opacity(0.3))
                .cornerRadius(DesignSystem.CornerRadius.small)

            if !isActive {
                Text("RESTORED")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.warning)
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.warning.opacity(0.1))
                    .cornerRadius(DesignSystem.CornerRadius.small)
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(isActive ? Color.clear : DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Add Custom Entity View

struct AddCustomEntityView: View {
    @ObservedObject var viewModel: AnonymizationViewModel
    @Binding var isPresented: Bool
    let initialText: String?
    @State private var searchText: String = ""
    @State private var selectedType: EntityType = .personOther

    init(viewModel: AnonymizationViewModel, isPresented: Binding<Bool>, initialText: String? = nil) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        self.initialText = initialText
        // Pre-fill search text if provided
        self._searchText = State(initialValue: initialText ?? "")
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header
            Text("Add Custom Redaction")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Text to Redact")
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                TextField("Enter text (case-insensitive search)", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignSystem.Typography.body)

                Text("This will find and redact all occurrences of this text")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Entity Type")
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Picker("Type", selection: $selectedType) {
                    // Recommended option first
                    HStack {
                        Image(systemName: EntityType.personOther.iconName)
                        Text("Other (Generic)")
                    }
                    .tag(EntityType.personOther)

                    Divider()

                    // All other types
                    ForEach(EntityType.allCases.filter { $0 != .personOther }) { type in
                        HStack {
                            Image(systemName: type.iconName)
                            Text(type.displayName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text("Tip: Use 'Other' for general sensitive information")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Actions
            HStack(spacing: DesignSystem.Spacing.medium) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Add Redaction") {
                    viewModel.addCustomEntity(text: searchText, type: selectedType)
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xlarge)
        .frame(width: 500, height: 380)
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

// MARK: - Interactive Text View

/// NSTextView wrapper that supports double-click word selection
struct InteractiveTextView: NSViewRepresentable {
    let attributedText: AttributedString
    let onDoubleClick: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // Set the attributed text
        textView.textStorage?.setAttributedString(NSAttributedString(attributedText))

        // Set up delegate for double-click detection
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Configure text container for wrapping
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update the attributed text
        textView.textStorage?.setAttributedString(NSAttributedString(attributedText))

        // Update the coordinator's callback
        context.coordinator.onDoubleClick = onDoubleClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var onDoubleClick: (String) -> Void

        init(onDoubleClick: @escaping (String) -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        // Detect when user double-clicks to select a word
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Since isEditable is false, this won't be called
            return false
        }

        // Alternative: detect selection changes after double-click
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Get the selected text
            let selectedRange = textView.selectedRange()

            // Only proceed if there's a selection
            guard selectedRange.length > 0 else { return }

            // Extract the selected word
            if let selectedText = textView.textStorage?.attributedSubstring(from: selectedRange).string {
                // Trim whitespace and newlines
                let word = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

                // Only trigger if it's a meaningful word (not just spaces)
                if !word.isEmpty {
                    // Trigger the callback with a slight delay to ensure it's a double-click
                    // Check if this is a double-click by monitoring click count
                    if let event = NSApp.currentEvent, event.clickCount == 2 {
                        onDoubleClick(word)
                    }
                }
            }
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
