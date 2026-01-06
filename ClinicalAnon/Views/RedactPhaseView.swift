//
//  RedactPhaseView.swift
//  Redactor
//
//  Purpose: First phase - text input and entity detection
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Redact Phase View

/// Phase 1: Input text, analyze, and manage entities
struct RedactPhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var showClassificationModal = false
    @State private var showAddMoreDocsModal = false

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
            AddCustomEntitySheet(viewModel: viewModel)
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
            DuplicateFinderModal(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.redactState.isEditingNameStructure) {
            if let entity = viewModel.redactState.nameStructureEditEntity {
                EditNameStructureModal(entity: entity, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.redactState.isSelectingVariant) {
            if let alias = viewModel.redactState.variantSelectionAlias,
               let primary = viewModel.redactState.variantSelectionPrimary {
                VariantSelectionModal(alias: alias, primary: primary, viewModel: viewModel)
            }
        }
        .alert("Deep Scan Complete", isPresented: $viewModel.redactState.showDeepScanCompleteMessage) {
            Button("OK") { }
        } message: {
            Text("Found \(viewModel.redactState.deepScanFindingsCount) additional term(s). These are shown but not active — tick any you want to redact, then click Apply Changes.")
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
                    ScrollView {
                        TextContentCard(isSourcePanel: true, isProcessed: true) {
                            Text(cachedOriginal)
                                .textSelection(.enabled)
                        }
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
                .background(.white)
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
                    ScrollView {
                        TextContentCard(isSourcePanel: false, isProcessed: false) {
                            Text(cachedRedacted)
                                .textSelection(.enabled)
                        }
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
                .background(.white)
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
                    Button(action: { Task { await viewModel.runLocalPIIReview() } }) {
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

                Button(action: { viewModel.continueToNextPhase() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(DesignSystem.Typography.body)
                    .frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canContinueFromRedact)
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
                                viewModel: viewModel,
                                isAISection: true
                            )
                        }

                        // Show Deep Scan section if there are deep scan findings
                        if !viewModel.deepScanFindings.isEmpty {
                            EntityTypeSection(
                                title: "Deep Scan Findings",
                                icon: "magnifyingglass.circle.fill",
                                color: .purple,
                                entities: viewModel.deepScanFindings,
                                viewModel: viewModel,
                                isAISection: false
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
                                    viewModel: viewModel,
                                    isAISection: false
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

// MARK: - Entity Type Section

private struct EntityTypeSection: View {
    let title: String
    let icon: String
    let color: Color
    let entities: [Entity]
    @ObservedObject var viewModel: WorkflowViewModel
    let isAISection: Bool

    @State private var isExpanded: Bool = true

    /// Check state: all included, all excluded, or mixed
    private var checkState: CheckState {
        let excludedCount = entities.filter { viewModel.isEntityExcluded($0) }.count
        if excludedCount == 0 {
            return .allIncluded
        } else if excludedCount == entities.count {
            return .allExcluded
        } else {
            return .mixed
        }
    }

    private enum CheckState {
        case allIncluded, allExcluded, mixed
    }

    /// Group entities: anchors with their children, sorted alphabetically by anchor
    private func groupedEntities() -> [(anchor: Entity, children: [Entity])] {
        // Separate anchors and children
        let anchors = entities.filter { $0.isAnchor }
        let children = entities.filter { !$0.isAnchor }

        // Group children by baseId
        var childrenByBaseId: [String: [Entity]] = [:]
        for child in children {
            if let baseId = child.baseId {
                childrenByBaseId[baseId, default: []].append(child)
            }
        }

        // Build groups: each anchor with its children
        var groups: [(anchor: Entity, children: [Entity])] = []
        for anchor in anchors.sorted(by: { $0.originalText.lowercased() < $1.originalText.lowercased() }) {
            let anchorChildren = anchor.baseId.flatMap { childrenByBaseId[$0] } ?? []
            // Sort children alphabetically within group
            let sortedChildren = anchorChildren.sorted { $0.originalText.lowercased() < $1.originalText.lowercased() }
            groups.append((anchor: anchor, children: sortedChildren))
        }

        return groups
    }

    /// Create entity row with optional indentation
    @ViewBuilder
    private func entityRow(for entity: Entity, indented: Bool) -> some View {
        HStack(spacing: 0) {
            if indented {
                // Indentation spacer for child entities
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
            }

            RedactEntityRow(
                entity: entity,
                isExcluded: viewModel.isEntityExcluded(entity),
                isFromAIReview: isAISection,
                isChild: indented,
                onToggle: { viewModel.toggleEntity(entity) },
                mergeTargets: viewModel.allEntities.filter { $0.type == entity.type && $0.id != entity.id }.sorted { $0.originalText.lowercased() < $1.originalText.lowercased() },
                onMerge: { target in viewModel.mergeEntities(alias: entity, into: target) },
                onEditNameStructure: { viewModel.redactState.startEditingNameStructure(entity) },
                onChangeType: { newType in viewModel.reclassifyEntity(entity.id, to: newType) }
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                // Toggle all checkbox
                Button(action: { viewModel.toggleEntities(entities) }) {
                    Image(systemName: checkState == .allIncluded ? "checkmark.square.fill" :
                                      checkState == .mixed ? "minus.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(checkState == .allExcluded ? DesignSystem.Colors.textSecondary : color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checkState == .allIncluded ? "Deselect all \(title)" : "Select all \(title)")

                // Expand/collapse button for rest of header
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(color)
                            .frame(width: 16)

                        Text(title.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("(\(entities.count))")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(title) section" : "Expand \(title) section")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .background(color.opacity(0.15))
            .cornerRadius(4)

            // Entity rows (grouped by anchor with children indented)
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(groupedEntities(), id: \.anchor.id) { group in
                        // Anchor row (no indent)
                        entityRow(for: group.anchor, indented: false)

                        // Child rows (indented)
                        ForEach(group.children) { child in
                            entityRow(for: child, indented: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Entity Row

private struct RedactEntityRow: View {

    let entity: Entity
    let isExcluded: Bool
    let isFromAIReview: Bool
    let isChild: Bool  // Whether this is an indented child entity
    let onToggle: () -> Void
    let mergeTargets: [Entity]
    let onMerge: (Entity) -> Void
    let onEditNameStructure: () -> Void
    let onChangeType: (EntityType) -> Void

    /// Text color: gray for excluded or child entities, primary for anchors
    private var textColor: Color {
        if isExcluded { return DesignSystem.Colors.textSecondary }
        return isChild ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Button(action: onToggle) {
                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                    .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : entity.type.highlightColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExcluded ? "Include \(entity.originalText) in redaction" : "Exclude \(entity.originalText) from redaction")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entity.originalText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                        .strikethrough(isExcluded)

                    if isFromAIReview {
                        Text("AI")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange)
                            .cornerRadius(3)
                    }
                }

                // Only show replacement code and variant badge for anchors, not children
                if !isChild {
                    HStack(spacing: 4) {
                        Text("→ \(entity.replacementCode)")
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        if let variant = entity.nameVariant {
                            Text(variant.displayName)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(entity.type.highlightColor.opacity(0.8))
                                .cornerRadius(3)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isExcluded ? Color.clear : (isFromAIReview ? Color.orange.opacity(0.1) : entity.type.highlightColor.opacity(0.1)))
        )
        .contextMenu {
            if !mergeTargets.isEmpty {
                Menu("Merge with...") {
                    ForEach(mergeTargets) { target in
                        Button("\(target.originalText) \(target.replacementCode)") {
                            onMerge(target)
                        }
                    }
                }
            }

            // Edit Name Structure - only for person types
            if entity.type.isPerson {
                Button(action: onEditNameStructure) {
                    Label("Edit Name Structure", systemImage: "person.text.rectangle")
                }
            }

            // Change Type submenu
            Menu("Change Type") {
                ForEach(EntityType.allCases.filter { $0 != entity.type }, id: \.self) { newType in
                    Button(newType.displayName) {
                        onChangeType(newType)
                    }
                }
            }
        }
    }
}

// MARK: - Add Custom Entity Sheet

struct AddCustomEntitySheet: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var text: String = ""
    @State private var selectedType: EntityType = .personClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("Add Custom Redaction")
                .font(DesignSystem.Typography.heading)

            TextField("Text to redact", text: $text)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    if let prefilled = viewModel.prefilledText {
                        text = prefilled
                    }
                }

            Picker("Entity Type", selection: $selectedType) {
                ForEach(EntityType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Add") {
                    viewModel.addCustomEntity(text: text, type: selectedType)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 350)
    }
}

// MARK: - Edit Name Structure Modal

struct EditNameStructureModal: View {

    let entity: Entity
    @ObservedObject var viewModel: WorkflowViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var middleName: String = ""
    @State private var lastName: String = ""
    @State private var title: String = ""

    private let titleOptions = ["", "Mr", "Mrs", "Ms", "Miss", "Dr", "Prof", "Rev"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Name Structure")
                    .font(DesignSystem.Typography.heading)
                Text(entity.baseReplacementCode)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Detected text reference
            HStack {
                Text("Detected:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text(entity.originalText)
                    .font(DesignSystem.Typography.caption)
                    .italic()
            }

            // Editable fields
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                LabeledContent("Title") {
                    Picker("", selection: $title) {
                        ForEach(titleOptions, id: \.self) { opt in
                            Text(opt.isEmpty ? "None" : opt).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                LabeledContent("First Name") {
                    TextField("First", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                LabeledContent("Middle Name") {
                    TextField("Middle (optional)", text: $middleName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                LabeledContent("Last Name") {
                    TextField("Last", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            // Preview of full name
            if !firstName.isEmpty || !lastName.isEmpty {
                HStack {
                    Text("Full name:")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(buildFullNamePreview())
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    viewModel.redactState.cancelNameStructureEdit()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Save") {
                    viewModel.redactState.saveNameStructure(
                        firstName: firstName,
                        middleName: middleName.isEmpty ? nil : middleName,
                        lastName: lastName,
                        title: title.isEmpty ? nil : title
                    )
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                         lastName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 350)
        .onAppear {
            loadExistingStructure()
        }
    }

    private func loadExistingStructure() {
        // Try to load existing RedactedPerson if available
        if let person = viewModel.engine.entityMapping.getPersonForCode(entity.replacementCode) {
            firstName = person.first
            middleName = person.middle ?? ""
            lastName = person.last
            title = person.detectedTitle ?? ""
        } else {
            // Parse from the entity's original text as default
            parseFromOriginalText()
        }
    }

    private func parseFromOriginalText() {
        let text = entity.originalText

        // Strip title if present
        let titles = ["Mr", "Mrs", "Ms", "Miss", "Dr", "Prof", "Rev", "Mr.", "Mrs.", "Ms.", "Dr.", "Prof."]
        var parts = text.components(separatedBy: " ").filter { !$0.isEmpty }

        if let firstPart = parts.first, titles.contains(where: { firstPart.lowercased() == $0.lowercased() }) {
            title = firstPart.replacingOccurrences(of: ".", with: "")
            parts.removeFirst()
        }

        // Assign parts to name fields
        if parts.count >= 1 {
            firstName = parts[0]
        }
        if parts.count >= 2 {
            lastName = parts[parts.count - 1]
        }
        if parts.count >= 3 {
            middleName = parts[1..<parts.count - 1].joined(separator: " ")
        }
    }

    private func buildFullNamePreview() -> String {
        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        if !firstName.isEmpty { parts.append(firstName) }
        if !middleName.isEmpty { parts.append(middleName) }
        if !lastName.isEmpty { parts.append(lastName) }
        return parts.joined(separator: " ")
    }
}

// MARK: - Variant Selection Modal

struct VariantSelectionModal: View {

    let alias: Entity
    let primary: Entity
    @ObservedObject var viewModel: WorkflowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Link Name to Anchor")
                    .font(DesignSystem.Typography.heading)
                Text("How should '\(alias.originalText)' be linked to '\(primary.originalText)'?")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Variant options
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Select the name type:")
                    .font(DesignSystem.Typography.body)

                Button(action: { selectVariant(.first) }) {
                    HStack {
                        Image(systemName: "person.fill")
                        VStack(alignment: .leading) {
                            Text("First Name")
                                .fontWeight(.medium)
                            Text("'\(alias.originalText)' is a first name or nickname")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: { selectVariant(.last) }) {
                    HStack {
                        Image(systemName: "person.2.fill")
                        VStack(alignment: .leading) {
                            Text("Last Name")
                                .fontWeight(.medium)
                            Text("'\(alias.originalText)' is a surname/family name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: { selectVariant(.firstLast) }) {
                    HStack {
                        Image(systemName: "person.text.rectangle")
                        VStack(alignment: .leading) {
                            Text("Full Name")
                                .fontWeight(.medium)
                            Text("'\(alias.originalText)' is the complete name")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Cancel button
            HStack {
                Button("Cancel") {
                    viewModel.redactState.cancelVariantSelection()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 400)
    }

    private func selectVariant(_ variant: NameVariant) {
        viewModel.completeMergeWithVariant(variant)
        dismiss()
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

// MARK: - Duplicate Finder Modal

struct DuplicateFinderModal: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [DuplicateGroup] = []

    private var highConfidenceGroups: [DuplicateGroup] {
        groups.filter { $0.confidence == .high }
    }

    private var lowConfidenceGroups: [DuplicateGroup] {
        groups.filter { $0.confidence == .low }
    }

    private var selectedGroups: [DuplicateGroup] {
        groups.filter { $0.isSelected }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Potential Duplicate Names")
                    .font(DesignSystem.Typography.heading)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close dialog")
            }
            .padding(DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if groups.isEmpty {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.success)

                    Text("No potential duplicates found")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text("All person entities appear to be unique")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.medium) {
                        // High Confidence Section
                        if !highConfidenceGroups.isEmpty {
                            DuplicateSection(
                                title: "High Confidence",
                                subtitle: "Full name matches with overlapping components",
                                color: DesignSystem.Colors.success,
                                groups: highConfidenceGroups,
                                onToggle: toggleGroup
                            )
                        }

                        // Low Confidence Section
                        if !lowConfidenceGroups.isEmpty {
                            DuplicateSection(
                                title: "Low Confidence",
                                subtitle: "Partial matches without full name anchor",
                                color: .orange,
                                groups: lowConfidenceGroups,
                                onToggle: toggleGroup
                            )
                        }
                    }
                    .padding(DesignSystem.Spacing.medium)
                }
            }

            Divider().opacity(0.15)

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                if !groups.isEmpty {
                    Text("\(selectedGroups.count) group\(selectedGroups.count == 1 ? "" : "s") selected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Button("Merge Selected") {
                    viewModel.mergeDuplicateGroups(selectedGroups)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedGroups.isEmpty)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .frame(width: 500, height: 450)
        .onAppear {
            groups = viewModel.redactState.findPotentialDuplicates()
        }
    }

    private func toggleGroup(_ group: DuplicateGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx].isSelected.toggle()
        }
    }
}

// MARK: - Duplicate Section

private struct DuplicateSection: View {

    let title: String
    let subtitle: String
    let color: Color
    let groups: [DuplicateGroup]
    let onToggle: (DuplicateGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            // Section header
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            // Groups
            ForEach(groups) { group in
                DuplicateGroupRow(group: group, onToggle: { onToggle(group) })
            }
        }
    }
}

// MARK: - Duplicate Group Row

private struct DuplicateGroupRow: View {

    let group: DuplicateGroup
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: group.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(group.isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(group.isSelected ? "Deselect merge group for \(group.primary.originalText)" : "Select merge group for \(group.primary.originalText)")

            // Group content
            VStack(alignment: .leading, spacing: 4) {
                // Primary entity
                HStack(spacing: 6) {
                    Text(group.primary.replacementCode)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(group.primary.type.highlightColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(group.primary.type.highlightColor.opacity(0.15))
                        .cornerRadius(3)

                    Text(group.primary.originalText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                // Matches
                ForEach(group.matches, id: \.id) { match in
                    HStack(spacing: 6) {
                        Text("├─")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(match.originalText)
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(match.replacementCode)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    }
                    .padding(.leading, 8)
                }
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(group.isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.08) : DesignSystem.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(group.isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.3) : DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
        )
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
