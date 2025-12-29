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
    #if ENABLE_AI_FEATURES
    private let setupManager: SetupManager
    #endif

    // MARK: - Initialization

    #if ENABLE_AI_FEATURES
    init(ollamaService: OllamaServiceProtocol, setupManager: SetupManager) {
        let engine = AnonymizationEngine(ollamaService: ollamaService)
        self.setupManager = setupManager
        _viewModel = StateObject(wrappedValue: AnonymizationViewModel(engine: engine, setupManager: setupManager))
    }
    #else
    init() {
        let engine = AnonymizationEngine()
        _viewModel = StateObject(wrappedValue: AnonymizationViewModel(engine: engine))
    }
    #endif

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Compact Header
            #if ENABLE_AI_FEATURES
            CompactHeaderView(setupManager: setupManager, viewModel: viewModel)
            #else
            CompactHeaderView(viewModel: viewModel)
            #endif

            // Main content with sidebar
            HStack(spacing: 0) {
                // Entity Management Sidebar (only show after analysis)
                if viewModel.result != nil {
                    EntityManagementSidebar(viewModel: viewModel)
                }

                // Three-pane content area
                HStack(spacing: 0) {
                    // LEFT PANE: Original Text (Card)
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

                    Divider()
                        .opacity(0.15)

                    // Text editor or highlighted text - fills all available space
                    if let result = viewModel.result, let cachedOriginal = viewModel.cachedOriginalAttributed {
                        // Show highlighted version with double-click support when we have results
                        InteractiveTextView(
                            attributedText: cachedOriginal,
                            onDoubleClick: { word in
                                viewModel.openAddCustomEntity(withText: word)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("original-highlighted-\(result.id)-\(viewModel.customEntities.count)")
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
                        .background(Color.clear)
                        .id("original-editor")
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(
                            viewModel.result != nil
                                ? DesignSystem.Colors.success.opacity(0.05)
                                : DesignSystem.Colors.surface
                        )
                )
                .cornerRadius(DesignSystem.CornerRadius.medium)
                .padding(6)
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
                                    Image(systemName: viewModel.justCopiedAnonymized ? "checkmark" : "doc.on.doc")
                                        .frame(width: 14, height: 14)
                                    Text(viewModel.justCopiedAnonymized ? "Copied!" : "Copy to AI")
                                        .frame(minWidth: 85)
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedAnonymized)
                        }
                    }
                    .frame(height: 52)
                    .padding(.horizontal, DesignSystem.Spacing.medium)

                    Divider()
                        .opacity(0.15)

                    // Redacted text display - fills all available space
                    if let result = viewModel.result, let cachedRedacted = viewModel.cachedRedactedAttributed {
                        ScrollView {
                            Text(cachedRedacted)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DesignSystem.Spacing.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("redacted-\(result.id)-\(viewModel.customEntities.count)")
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
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(
                            viewModel.hasCopiedRedacted
                                ? DesignSystem.Colors.success.opacity(0.05)
                                : DesignSystem.Colors.surface
                        )
                        .shadow(
                            color: DesignSystem.Elevation.lifted.shadowColor,
                            radius: DesignSystem.Elevation.lifted.shadowRadius,
                            x: DesignSystem.Elevation.lifted.shadowX,
                            y: DesignSystem.Elevation.lifted.shadowY
                        )
                )
                .cornerRadius(DesignSystem.CornerRadius.medium)
                .padding(6)
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
                                    Image(systemName: viewModel.justCopiedRestored ? "checkmark" : "doc.on.doc")
                                        .frame(width: 14, height: 14)
                                    Text(viewModel.justCopiedRestored ? "Copied!" : "Copy")
                                        .frame(minWidth: 70)
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedRestored)
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

                    Divider()
                        .opacity(0.15)

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
                            if let cachedRestored = viewModel.cachedRestoredAttributed {
                                Text(cachedRestored)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DesignSystem.Spacing.medium)
                            } else {
                                Text(MarkdownParser.parseToAttributedString(viewModel.restoredText, baseFont: .systemFont(ofSize: 14)))
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
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(
                            viewModel.hasRestoredText
                                ? DesignSystem.Colors.success.opacity(0.05)
                                : DesignSystem.Colors.surface
                        )
                )
                .cornerRadius(DesignSystem.CornerRadius.medium)
                .padding(6)
                .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background)

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
        // Parse Markdown formatting first
        var attributedString = MarkdownParser.parseToAttributedString(restoredText, baseFont: .systemFont(ofSize: 14))

        // Apply default text color
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
    #if ENABLE_AI_FEATURES
    let setupManager: SetupManager
    #endif
    @ObservedObject var viewModel: AnonymizationViewModel
    @State private var showingHelp = false

    #if ENABLE_AI_FEATURES
    init(setupManager: SetupManager, viewModel: AnonymizationViewModel) {
        self.setupManager = setupManager
        self.viewModel = viewModel
    }
    #else
    init(viewModel: AnonymizationViewModel) {
        self.viewModel = viewModel
    }
    #endif

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Text("Redactor")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            Spacer()

            #if ENABLE_AI_FEATURES
            // Detection mode picker
            DetectionModePicker(engine: viewModel.engine)

            // Model info
            ModelBadge(setupManager: setupManager)
            #endif

            // Help button
            Button(action: { showingHelp = true }) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 18))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
            }
            .buttonStyle(.plain)
            .help("How to use Redactor")
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $showingHelp) {
            HelpModalView(isPresented: $showingHelp)
        }
    }
}

// MARK: - Model Picker

#if ENABLE_AI_FEATURES
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
#endif


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

    // Performance: Cached redacted text to avoid recomputation on every access
    @Published private(set) var cachedRedactedText: String = ""
    private var redactedTextNeedsUpdate: Bool = true
    private var toggleDebounceTask: DispatchWorkItem?

    // Performance: Cached AttributedStrings to avoid recomputing highlights on every toggle
    @Published private(set) var cachedOriginalAttributed: AttributedString?
    @Published private(set) var cachedRedactedAttributed: AttributedString?
    @Published private(set) var cachedRestoredAttributed: AttributedString?

    // Private backing store for excluded IDs - changes don't trigger view re-render
    private var _excludedIds: Set<UUID> = []

    // Add custom entity dialog state
    @Published var showingAddCustom: Bool = false
    @Published var prefilledText: String? = nil

    // Copy button feedback
    @Published var justCopiedAnonymized: Bool = false
    @Published var justCopiedOriginal: Bool = false
    @Published var justCopiedRestored: Bool = false

    // Completion state for card color changes
    @Published var hasCopiedRedacted: Bool = false
    @Published var hasRestoredText: Bool = false

    // MARK: - Properties (accessible for UI)

    let engine: AnonymizationEngine
    #if ENABLE_AI_FEATURES
    let setupManager: SetupManager
    #endif

    // Detection mode from engine (forwarding)
    var detectionMode: DetectionMode {
        get { engine.detectionMode }
        set { engine.detectionMode = newValue }
    }

    // MARK: - Initialization

    #if ENABLE_AI_FEATURES
    init(engine: AnonymizationEngine, setupManager: SetupManager) {
        self.engine = engine
        self.setupManager = setupManager
    }
    #else
    init(engine: AnonymizationEngine) {
        self.engine = engine
    }
    #endif

    // MARK: - Entity Management Computed Properties

    /// All entities (detected + custom)
    var allEntities: [Entity] {
        guard let result = result else { return customEntities }
        return result.entities + customEntities
    }

    /// Only active entities (not excluded) - uses private backing store for performance
    var activeEntities: [Entity] {
        allEntities.filter { !_excludedIds.contains($0.id) }
    }

    /// Check if an entity is excluded (for UI bindings)
    func isEntityExcluded(_ entity: Entity) -> Bool {
        _excludedIds.contains(entity.id)
    }

    /// Dynamically generated redacted text based on active entities
    /// Uses cached version for performance - call updateRedactedTextCache() when entities change
    var displayedRedactedText: String {
        if redactedTextNeedsUpdate {
            updateRedactedTextCache()
        }
        return cachedRedactedText
    }

    /// Update the cached redacted text - called when entities or exclusions change
    private func updateRedactedTextCache() {
        guard let result = result else {
            cachedRedactedText = ""
            redactedTextNeedsUpdate = false
            return
        }

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
                continue
            }

            let start = text.index(text.startIndex, offsetBy: replacement.start)
            let end = text.index(text.startIndex, offsetBy: replacement.end)

            // Validate string indices before replacement
            guard start < text.endIndex && end <= text.endIndex && start < end else {
                continue
            }

            text.replaceSubrange(start..<end, with: replacement.code)
        }

        cachedRedactedText = text
        redactedTextNeedsUpdate = false
    }

    // MARK: - Cached AttributedString Management

    /// Rebuild all cached AttributedStrings - called after analyze() or when entities change
    func rebuildAllHighlightCaches() {
        guard let result = result else {
            cachedOriginalAttributed = nil
            cachedRedactedAttributed = nil
            cachedRestoredAttributed = nil
            return
        }

        // Build all three caches using current _excludedIds state
        cachedOriginalAttributed = buildOriginalAttributed(result.originalText)
        cachedRedactedAttributed = buildRedactedAttributed()
        cachedRestoredAttributed = buildRestoredAttributed()
    }

    /// Build highlighted AttributedString for original text using entity positions
    private func buildOriginalAttributed(_ text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Apply highlights using stored positions (O(n) - no text search!)
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

                // Convert Int positions to AttributedString indices
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

    /// Build highlighted AttributedString for redacted text
    private func buildRedactedAttributed() -> AttributedString {
        let text = displayedRedactedText
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight replacement codes for active entities
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

    /// Build highlighted AttributedString for restored text
    private func buildRestoredAttributed() -> AttributedString {
        guard let result = result else { return AttributedString("") }

        // Parse Markdown formatting first
        var attributedString = MarkdownParser.parseToAttributedString(restoredText, baseFont: .systemFont(ofSize: 14))
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight restored entities using text search (restored text may have moved)
        for entity in result.entities {
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

    /// Update highlights for a single entity toggle - much faster than full rebuild
    func updateHighlightsForToggle(_ entity: Entity, isNowExcluded: Bool) {
        guard let result = result else { return }

        // Update original text highlighting for this entity only
        if var original = cachedOriginalAttributed {
            let text = result.originalText
            let bgColor = isNowExcluded
                ? NSColor.gray.withAlphaComponent(0.3)
                : NSColor(entity.type.highlightColor)
            let fgColor = isNowExcluded
                ? NSColor(DesignSystem.Colors.textSecondary)
                : NSColor(DesignSystem.Colors.textPrimary)

            for position in entity.positions {
                guard position.count >= 2 else { continue }
                let start = position[0]
                let end = position[1]

                guard start >= 0 && end <= text.count && start < end else { continue }

                let startIdx = original.index(original.startIndex, offsetByCharacters: start)
                let endIdx = original.index(original.startIndex, offsetByCharacters: end)

                guard startIdx < original.endIndex && endIdx <= original.endIndex else { continue }

                original[startIdx..<endIdx].backgroundColor = bgColor
                original[startIdx..<endIdx].foregroundColor = fgColor
            }

            cachedOriginalAttributed = original
        }

        // Redacted and restored need full rebuild as the text content changes
        redactedTextNeedsUpdate = true
        _ = displayedRedactedText  // Force cache update
        cachedRedactedAttributed = buildRedactedAttributed()

        // Only rebuild restored if there's restored text
        if !restoredText.isEmpty {
            cachedRestoredAttributed = buildRestoredAttributed()
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

        #if ENABLE_AI_FEATURES
        // Update model name from setup manager before processing
        engine.updateModelName(setupManager.selectedModel)
        #endif

        // Dismiss previous messages
        errorMessage = nil
        successMessage = nil

        // Reset completion states for new analysis
        hasCopiedRedacted = false
        hasRestoredText = false

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
    }

    func clearInputText() {
        inputText = ""
    }

    func copyInputText() {
        copyToClipboard(inputText)

        // Visual feedback on button
        justCopiedOriginal = true
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            justCopiedOriginal = false
        }
    }

    func copyAnonymizedText() {
        guard result != nil else { return }
        let text = displayedRedactedText
        copyToClipboard(text)

        // Visual feedback on button
        justCopiedAnonymized = true
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            justCopiedAnonymized = false
        }

        // Mark card as complete
        hasCopiedRedacted = true
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

        // Mark card as complete
        hasRestoredText = true

        print("✅ Restoration complete")
    }

    func copyRestoredText() {
        guard !restoredText.isEmpty else { return }
        copyFormattedToClipboard(restoredText)

        // Visual feedback on button
        justCopiedRestored = true
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            justCopiedRestored = false
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissSuccess() {
        successMessage = nil
    }

    // MARK: - Entity Management Actions

    /// Toggle an entity on/off - instant, no processing
    /// Call applyChanges() to update text panes
    func toggleEntity(_ entity: Entity) {
        // Toggle in backing store only (instant)
        if _excludedIds.contains(entity.id) {
            _excludedIds.remove(entity.id)
        } else {
            _excludedIds.insert(entity.id)
        }
        hasPendingChanges = true
    }

    /// Check if there are unapplied toggle changes
    @Published var hasPendingChanges: Bool = false

    /// Apply all pending toggle changes - rebuilds text panes
    func applyChanges() {
        guard hasPendingChanges else { return }

        // Sync to published property
        excludedEntityIds = _excludedIds

        // Rebuild caches
        redactedTextNeedsUpdate = true
        rebuildAllHighlightCaches()

        hasPendingChanges = false
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

        // Invalidate cache so it rebuilds with new entity
        redactedTextNeedsUpdate = true

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

    private func copyFormattedToClipboard(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Copy as RTF for Word compatibility, with plain text fallback
        if let rtfData = MarkdownParser.parseToRTFData(markdown) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        // Also include plain text as fallback for apps that don't support RTF
        pasteboard.setString(markdown, forType: .string)
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
    @State private var sidebarWidth: CGFloat = 270

    var body: some View {
        HStack(spacing: 0) {
            // Resize handle
            if !isCollapsed {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = sidebarWidth - value.translation.width
                                sidebarWidth = min(max(newWidth, 200), 400)
                            }
                    )
            }

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
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.medium)

            if !isCollapsed {
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
                                    isActive: !viewModel.isEntityExcluded(entity),
                                    onToggle: { viewModel.toggleEntity(entity) }
                                )
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.small)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                    }

                    // Apply Changes button - only shown when there are pending changes
                    if viewModel.hasPendingChanges {
                        Button(action: { viewModel.applyChanges() }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Apply Changes")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.primaryTeal)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignSystem.Spacing.small)
                        .padding(.bottom, DesignSystem.Spacing.small)
                    }
                }
            }
        }
        .background(DesignSystem.Colors.surface)
        .frame(maxHeight: .infinity)
        .frame(width: isCollapsed ? 40 : sidebarWidth)
        }
        .sheet(isPresented: $viewModel.showingAddCustom) {
            AddCustomEntityView(viewModel: viewModel, isPresented: $viewModel.showingAddCustom, initialText: viewModel.prefilledText)
        }
    }
}

struct EntitySidebarRow: View {
    let entity: Entity
    let isActive: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(
                    isHovered
                        ? DesignSystem.Colors.primaryTeal.opacity(0.08)
                        : (isActive ? Color.clear : DesignSystem.Colors.surface.opacity(0.5))
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
                                isActive: !viewModel.isEntityExcluded(entity),
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

// MARK: - Detection Mode Picker

#if ENABLE_AI_FEATURES
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
#endif

// MARK: - Interactive Text View

/// NSTextView wrapper that supports double-click word selection
struct InteractiveTextView: NSViewRepresentable {
    let attributedText: AttributedString
    let onDoubleClick: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
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
        #if ENABLE_AI_FEATURES
        AnonymizationView(
            ollamaService: OllamaService(mockMode: true),
            setupManager: SetupManager.preview
        )
        .frame(width: 1200, height: 700)
        #else
        AnonymizationView()
        .frame(width: 1200, height: 700)
        #endif
    }
}

// MARK: - Help Modal View

struct HelpModalView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("How to Use Redactor")
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(DesignSystem.Spacing.large)
            .background(DesignSystem.Colors.surface)

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {

                    // Why use this app?
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Why use this app?")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text("AI tools like Claude can help you write clearer, more structured clinical notes. But you can't paste client information directly into AI tools - it's not safe or ethical.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("Redactor lets you safely use AI to improve your clinical writing. It removes identifying information, you get AI help, then it puts the details back.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }

                    Divider()
                        .opacity(0.3)

                    // The 5-Step Process
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Text("The 5-Step Process")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        // Step 1
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Text("①")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste your text")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Write or paste your clinical notes into the left column (Original Text).")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }

                        // Step 2
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Text("②")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Click \"Analyze\"")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Redactor detects names, dates, locations, and other identifying information. Check the sidebar to see what was found.")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }

                        // Step 3
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Text("③")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Copy the redacted version")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Click \"Copy to AI\" in the middle column. The text now has placeholders like [PERSON_A] instead of real names.")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }

                        // Step 4
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Text("④")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Get AI help")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Open Claude or ChatGPT. Paste the redacted text. Ask the AI to improve clarity, structure, or grammar. Copy the AI's response.")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }

                        // Step 5
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                            Text("⑤")
                                .font(.system(size: 20))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste back and restore")
                                    .font(DesignSystem.Typography.bodyBold)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Text("Paste the AI-improved text into the right column (Restored Text). Click \"Restore Names\" and Redactor automatically puts all the real information back.")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }

                        // Done
                        Text("Done. You now have a better note with all client details intact.")
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                            .padding(.leading, 38)
                    }

                    Divider()
                        .opacity(0.3)

                    // Managing Entities
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Managing Entities")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text("The sidebar shows everything Redactor detected. You can:")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Toggle entities on/off - uncheck items you want to keep")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Add custom entities - click the + button for anything Redactor missed")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Review before copying - always double-check what's been redacted")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .padding(.leading, DesignSystem.Spacing.small)

                        Text("Not everything gets caught automatically. Always review the sidebar before copying.")
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.top, 4)
                    }

                    Divider()
                        .opacity(0.3)

                    // Need to Start Fresh?
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Need to Start Fresh?")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text("Click \"Clear All\" at the bottom to wipe everything and start a new note.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }

                    Divider()
                        .opacity(0.3)

                    // Settings & Whitelist
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Settings & Whitelist")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text("Some words get flagged incorrectly (like organisation names or clinical terms). You can permanently exclude them:")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Press ⌘, (Cmd + comma) to open Settings")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Add words you want to whitelist - they'll never be flagged again")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Import/export your whitelist as a comma-separated list")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .padding(.leading, DesignSystem.Spacing.small)

                        Text("Your whitelist is saved permanently and applies to all documents.")
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .padding(.top, 4)
                    }

                    Divider()
                        .opacity(0.3)

                    // Tips
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Tips")
                            .font(DesignSystem.Typography.subheading)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Redactor works completely offline - nothing leaves your Mac")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Text isn't saved anywhere - it's cleared when you close the app")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }

                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundColor(DesignSystem.Colors.primaryTeal)
                                Text("Use it for reports, assessments, and session notes")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .padding(.leading, DesignSystem.Spacing.small)
                    }
                }
                .padding(DesignSystem.Spacing.large)
            }
            .background(DesignSystem.Colors.background)
        }
        .frame(width: 600, height: 750)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.large)
        .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 10)
    }
}

#endif
