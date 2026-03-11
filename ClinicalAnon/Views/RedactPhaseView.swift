//
//  RedactPhaseView.swift
//  Redactor
//
//  Purpose: First phase - text input and entity detection
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Redact Phase View

/// Phase 1: Input text, analyze, and manage entities
struct RedactPhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var showClassificationModal = false
    @State private var showAddMoreDocsModal = false
    @State private var showLLMDownloadSheet = false
    @State private var showPendingChangesAlert = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Entity sidebar (only show after analysis)
            if viewModel.result != nil {
                RedactEntitySidebar(viewModel: viewModel)
            }

            // Main content area with footer
            VStack(spacing: 0) {
                // Two-pane content: Original | Redacted (equal widths)
                GeometryReader { geometry in
                    let paneWidth = (geometry.size.width) / 2

                    HStack(spacing: 0) {
                        // LEFT: Original Text
                        originalTextPane
                            .frame(width: paneWidth)

                        // RIGHT: Redacted Text
                        redactedTextPane
                            .frame(width: paneWidth)
                    }
                }

                // Footer bar spanning both panes (only after analysis)
                if viewModel.result != nil {
                    actionFooter
                }
            }
        }
        .sheet(isPresented: $viewModel.showingAddCustom) {
            AddCustomEntitySheet(
                prefilledText: viewModel.prefilledText,
                onAdd: { text, type in viewModel.addCustomEntity(text: text, type: type) }
            )
        }
        .sheet(isPresented: $showClassificationModal) {
            TextClassificationModal(
                selectedType: $viewModel.redactState.textInputType,
                otherDescription: $viewModel.redactState.textInputTypeDescription,
                onAnalyze: {
                    showClassificationModal = false
                    Task { await viewModel.analyze() }
                }
            )
        }
        .sheet(isPresented: $showAddMoreDocsModal) {
            TextClassificationModal(
                selectedType: $viewModel.redactState.textInputType,
                otherDescription: $viewModel.redactState.textInputTypeDescription,
                actionTitle: "Save & Add Another",
                headerText: "Classify this document before saving",
                onAnalyze: {
                    showAddMoreDocsModal = false
                    viewModel.saveCurrentDocumentAndAddMore()
                }
            )
        }
        .sheet(isPresented: $viewModel.redactState.showDuplicateFinderModal) {
            DuplicateFinderModal(
                findDuplicates: { viewModel.redactState.findPotentialDuplicates() },
                onMergeGroups: { viewModel.mergeDuplicateGroups($0) }
            )
        }
        .sheet(isPresented: $viewModel.redactState.isEditingNameStructure) {
            if let entity = viewModel.redactState.nameStructureEditEntity {
                EditNameStructureModal(
                    entity: entity,
                    onSave: { first, middle, last, title in
                        viewModel.redactState.saveNameStructure(
                            firstName: first, middleName: middle, lastName: last, title: title
                        )
                    },
                    onCancel: { viewModel.redactState.cancelNameStructureEdit() },
                    getPersonForCode: { viewModel.engine.entityMapping.getPersonForCode($0) }
                )
            }
        }
        .alert("Deep Scan Complete", isPresented: $viewModel.redactState.showDeepScanCompleteMessage) {
            Button("OK") { }
        } message: {
            Text("Found \(viewModel.redactState.deepScanFindingsCount) additional term(s). These are shown but not active — tick any you want to redact, then click Apply Changes.")
        }
        .sheet(isPresented: $showLLMDownloadSheet) {
            DeepScanDownloadSheet(
                modelSize: LocalLLMService.shared.selectedModelInfo?.size ?? "2 GB",
                onConfirm: {
                    Task {
                        await viewModel.runLocalPIIReviewWithDownload()
                        showLLMDownloadSheet = false
                    }
                },
                onCancel: {
                    showLLMDownloadSheet = false
                }
            )
        }
    }

    // MARK: - Original Text Pane

    private var originalTextPane: some View {
        VStack(spacing: 0) {
            // Title bar with Analyze button
            HStack {
                Text("Original Text")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                if !viewModel.inputText.isEmpty {
                    Text("\(viewModel.inputText.wordCount) words")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.trailing, DesignSystem.Spacing.small)
                }

                Button(action: { showClassificationModal = true }) {
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

            Divider().opacity(0.15)

            // Text content
            if let result = viewModel.result {
                if let cachedOriginal = viewModel.cachedOriginalAttributed {
                    TextContentCard(isSourcePanel: true, isProcessed: true) {
                        FastTextView(
                            attributedText: cachedOriginal,
                            onRightClick: { selectedText in
                                viewModel.openAddCustomEntity(withText: selectedText)
                            },
                            onRemoveEntity: { selectedText in
                                viewModel.removeEntitiesByText(selectedText)
                            },
                            getAnchorName: { selectedText in
                                viewModel.redactState.getAnchorNameForText(selectedText)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id("original-highlighted-\(result.id)-\(viewModel.customEntities.count)")
                } else {
                    // Show plain text while highlights build
                    ScrollView {
                        TextContentCard(isSourcePanel: true, isProcessed: true) {
                            Text(result.originalText)
                                .textSelection(.enabled)
                                .font(.system(size: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if viewModel.isProcessing {
                // Processing state - show loading indicator
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Analyzing text...")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text("This may take a few minutes for large documents.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                .padding(24)
            } else {
                // Initial input state - card fills pane
                ZStack(alignment: .topLeading) {
                    if viewModel.inputText.isEmpty {
                        Text("Paste clinical text here to anonymize...")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                            .padding(32)
                    }

                    TextEditor(text: $viewModel.inputText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                .padding(24)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.panelWarm)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
    }

    // MARK: - Redacted Text Pane

    private var redactedTextPane: some View {
        VStack(spacing: 0) {
            // Title bar with Copy and Continue buttons
            HStack {
                Text("Redacted Text")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                // Show saved document count badge
                if !viewModel.sourceDocuments.isEmpty {
                    Text("\(viewModel.sourceDocuments.count) doc\(viewModel.sourceDocuments.count == 1 ? "" : "s") saved")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primaryTeal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .cornerRadius(4)
                }

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
                            Text(viewModel.justCopiedAnonymized ? "Copied!" : "Copy")
                                .frame(minWidth: 50)
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedAnonymized)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Redacted text content
            if let result = viewModel.result {
                if let cachedRedacted = viewModel.cachedRedactedAttributed {
                    TextContentCard(isSourcePanel: false, isProcessed: false) {
                        FastTextView(
                            attributedText: cachedRedacted,
                            onRightClick: { selectedText in
                                viewModel.openAddCustomEntity(withText: selectedText)
                            },
                            onRemoveEntity: { selectedText in
                                viewModel.removeEntitiesByText(selectedText)
                            },
                            getAnchorName: { selectedText in
                                viewModel.redactState.getAnchorNameForText(selectedText)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id("redacted-\(result.id)-\(viewModel.customEntities.count)")
                } else {
                    // Show plain redacted text while highlights build
                    ScrollView {
                        TextContentCard(isSourcePanel: false, isProcessed: false) {
                            Text(viewModel.displayedRedactedText)
                                .textSelection(.enabled)
                                .font(.system(size: 14))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Empty state - card fills pane with centered content
                VStack {
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
                .background(DesignSystem.Colors.surface)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                .padding(24)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.panelNeutral)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Divider().opacity(0.15)

            // Status messages
            if let error = viewModel.errorMessage {
                ErrorBanner(
                    message: error,
                    onDismiss: { viewModel.errorMessage = nil }
                )
            }

            if let success = viewModel.successMessage {
                SuccessBanner(
                    message: success,
                    onDismiss: nil
                )
            }

            // Buttons
            HStack {
                Spacer()

                // LLM Scan button (if local LLM available)
                if LocalLLMService.shared.isAvailable {
                    Button(action: {
                        // Check if model needs to be downloaded first
                        if LocalLLMService.shared.isModelCached {
                            // Model is cached - run directly
                            Task { await viewModel.runLocalPIIReview() }
                        } else {
                            // Model not cached - show download confirmation sheet
                            showLLMDownloadSheet = true
                        }
                    }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            if viewModel.isReviewingPII {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "brain")
                            }
                            Text("LLM Scan")
                        }
                        .font(DesignSystem.Typography.body)
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(viewModel.isReviewingPII)
                    .help("Scan for missed PII using local AI")
                }

                // Deep Scan button (Apple NER at lower confidence)
                Button(action: { Task { await viewModel.runDeepScan() } }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        if viewModel.isRunningDeepScan {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        Text("Deep Scan")
                    }
                    .font(DesignSystem.Typography.body)
                    .frame(minWidth: 120)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isRunningDeepScan)
                .help("Run Apple NER with lower confidence (0.75) to catch additional names")

                // Add More Docs button - shows classification modal first
                Button(action: { showAddMoreDocsModal = true }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "doc.badge.plus")
                        Text("Add More Docs")
                    }
                    .font(DesignSystem.Typography.body)
                    .frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canContinueFromRedact || viewModel.hasPendingChanges)
                .help("Save this document and add another source document")

                Button(action: {
                    if viewModel.hasPendingChanges {
                        showPendingChangesAlert = true
                    } else {
                        viewModel.continueToNextPhase()
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(DesignSystem.Typography.body)
                    .frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.result == nil)
                .alert("Unapplied Changes", isPresented: $showPendingChangesAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Apply & Continue") {
                        viewModel.applyChanges()
                        viewModel.continueToNextPhase()
                    }
                } message: {
                    Text("You have entity changes that haven't been applied. Apply them and continue?")
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Entity Management Sidebar (Wrapper)

/// Sidebar for entity management using WorkflowViewModel
private struct RedactEntitySidebar: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var isCollapsed: Bool = false
    @State private var showAddTooltip: Bool = false
    @State private var showDuplicateTooltip: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if !isCollapsed {
                    Text("Entities (\(viewModel.allEntities.count))")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    Button(action: { viewModel.openAddCustomEntity() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .onHover { showAddTooltip = $0 }
                    .overlay(alignment: .bottom) {
                        if showAddTooltip {
                            Text("Add custom entity")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(4)
                                .offset(y: 24)
                        }
                    }
                    .accessibilityLabel("Add custom entity")

                    Button(action: { viewModel.openDuplicateFinder() }) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .onHover { showDuplicateTooltip = $0 }
                    .overlay(alignment: .bottom) {
                        if showDuplicateTooltip {
                            Text("Find duplicate names")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(4)
                                .offset(y: 24)
                        }
                    }
                    .accessibilityLabel("Find duplicate names")
                    .disabled(personEntityCount < 2)
                    .opacity(personEntityCount < 2 ? 0.4 : 1.0)
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            if !isCollapsed {
                Divider().opacity(0.15)

                // Entity list grouped by type
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.small) {
                        // Show AI Review section if there are AI findings
                        if !viewModel.piiReviewFindings.isEmpty {
                            EntityTypeSection(
                                title: "AI Review Findings",
                                icon: "sparkles",
                                color: .orange,
                                entities: viewModel.piiReviewFindings,
                                actions: entityActions,
                                isAISection: true,
                                isDeepScanSection: false
                            )
                        }

                        // Show Deep Scan section if there are deep scan findings
                        if !viewModel.deepScanFindings.isEmpty {
                            EntityTypeSection(
                                title: "Deep Scan Findings",
                                icon: "magnifyingglass.circle.fill",
                                color: .purple,
                                entities: viewModel.deepScanFindings,
                                actions: entityActions,
                                isAISection: false,
                                isDeepScanSection: true
                            )
                        }

                        // Group entities by type
                        ForEach(groupedEntityTypes, id: \.self) { entityType in
                            let entities = entitiesForType(entityType)
                            if !entities.isEmpty {
                                EntityTypeSection(
                                    title: entityType.displayName,
                                    icon: entityType.iconName,
                                    color: entityType.highlightColor,
                                    entities: entities,
                                    actions: entityActions,
                                    isAISection: false,
                                    isDeepScanSection: false
                                )
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.small)
                }

                // Apply Changes button (if pending)
                if viewModel.hasPendingChanges {
                    Divider().opacity(0.15)

                    Button(action: { viewModel.applyChanges() }) {
                        Text("Apply Changes")
                            .font(DesignSystem.Typography.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(DesignSystem.Spacing.small)
                }
            }
        }
        .frame(width: isCollapsed ? 40 : 270)
        .background(DesignSystem.Colors.surface)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }

    // MARK: - Entity Actions

    private var entityActions: EntityActions {
        EntityActions(
            isEntityExcluded: { viewModel.isEntityExcluded($0) },
            toggleEntity: { viewModel.toggleEntity($0) },
            toggleEntities: { viewModel.toggleEntities($0) },
            mergeEntities: { alias, primary in viewModel.mergeEntities(alias: alias, into: primary) },
            startEditingNameStructure: { viewModel.redactState.startEditingNameStructure($0) },
            reclassifyEntity: { id, type in viewModel.reclassifyEntity(id, to: type) },
            allEntities: viewModel.allEntities
        )
    }

    // MARK: - Computed Properties

    /// Count of person entities (for duplicate finder button)
    private var personEntityCount: Int {
        viewModel.allEntities.filter { $0.type.isPerson && !viewModel.isEntityExcluded($0) }.count
    }

    // MARK: - Grouping Helpers

    /// Entity types in display order (excluding AI findings which are shown separately)
    private var groupedEntityTypes: [EntityType] {
        [.personClient, .personProvider, .personOther, .date, .location, .organization, .contact, .identifier, .numericAll]
    }

    /// Get entities for a specific type (excluding AI/deep scan findings shown in separate sections)
    private func entitiesForType(_ type: EntityType) -> [Entity] {
        let aiIds = Set(viewModel.piiReviewFindings.map { $0.id })
        let deepIds = Set(viewModel.deepScanFindings.map { $0.id })
        return viewModel.allEntities.filter {
            $0.type == type && !aiIds.contains($0.id) && !deepIds.contains($0.id)
        }
    }
}

// MARK: - Text Classification Modal

struct TextClassificationModal: View {

    @Binding var selectedType: TextInputType
    @Binding var otherDescription: String
    var actionTitle: String = "Analyze"
    var headerText: String = "What type of text is this?"
    let onAnalyze: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            headerSection
            optionsList
            otherDescriptionField
            buttonRow
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 450)
    }

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Text(headerText)
                .font(DesignSystem.Typography.heading)

            Text("This helps the AI understand how to process your content")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var optionsList: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            ForEach(TextInputType.allCases, id: \.self) { type in
                optionButton(for: type)
            }
        }
    }

    private func optionButton(for type: TextInputType) -> some View {
        let isSelected = selectedType == type
        return Button(action: { selectedType = type }) {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : DesignSystem.Colors.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)

                    Text(type.description)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : DesignSystem.Colors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .stroke(isSelected ? Color.clear : DesignSystem.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var otherDescriptionField: some View {
        if selectedType == .other {
            TextField("Describe your content...", text: $otherDescription)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var buttonRow: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(actionTitle) {
                onAnalyze()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Preview

#if DEBUG
struct RedactPhaseView_Previews: PreviewProvider {
    static var previews: some View {
        RedactPhaseView(viewModel: WorkflowViewModel())
            .frame(width: 900, height: 600)
    }
}
#endif
