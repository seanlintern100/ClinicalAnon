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

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Entity sidebar (only show after analysis)
            if viewModel.result != nil {
                RedactEntitySidebar(viewModel: viewModel)
            }

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
        }
        .sheet(isPresented: $viewModel.showingAddCustom) {
            AddCustomEntitySheet(viewModel: viewModel)
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

            Divider().opacity(0.15)

            // Text content
            if let result = viewModel.result, let cachedOriginal = viewModel.cachedOriginalAttributed {
                ScrollView {
                    Text(cachedOriginal)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id("original-highlighted-\(result.id)-\(viewModel.customEntities.count)")
            } else {
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
    }

    // MARK: - Redacted Text Pane

    private var redactedTextPane: some View {
        VStack(spacing: 0) {
            // Title bar with Copy and Continue buttons
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
            }

            // LLM Scan and Continue buttons at bottom
            if viewModel.result != nil {
                Divider().opacity(0.15)

                VStack(spacing: DesignSystem.Spacing.small) {
                    // Status messages
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(.red)
                            Spacer()
                            Button(action: { viewModel.errorMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(DesignSystem.Spacing.small)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }

                    if let success = viewModel.successMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(success)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(DesignSystem.Spacing.small)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
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
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(viewModel.isReviewingPII)
                            .help("Scan for missed PII using local AI")
                        }

                        // BERT NER Scan button
                        if BertNERService.shared.isAvailable {
                            Button(action: { Task { await viewModel.runBertNERScan() } }) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    if viewModel.isRunningBertNER {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "text.viewfinder")
                                    }
                                    Text("BERT Scan")
                                }
                                .font(DesignSystem.Typography.body)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(viewModel.isRunningBertNER)
                            .help("Scan using BERT NER model for names, organizations, and locations")
                        }

                        // XLM-R NER Scan button (multilingual)
                        if XLMRobertaNERService.shared.isAvailable {
                            Button(action: { Task { await viewModel.runXLMRNERScan() } }) {
                                HStack(spacing: DesignSystem.Spacing.xs) {
                                    if viewModel.isRunningXLMRNER {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "globe.americas.fill")
                                    }
                                    Text("XLM-R Scan")
                                }
                                .font(DesignSystem.Typography.body)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(viewModel.isRunningXLMRNER)
                            .help("Scan using XLM-RoBERTa multilingual NER for foreign names (100+ languages)")
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
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(viewModel.isRunningDeepScan)
                        .help("Run Apple NER with lower confidence (0.75) to catch additional names")

                        Button(action: { viewModel.continueToNextPhase() }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .font(DesignSystem.Typography.body)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.canContinueFromRedact)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
    }
}

// MARK: - Entity Management Sidebar (Wrapper)

/// Sidebar for entity management using WorkflowViewModel
private struct RedactEntitySidebar: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var isCollapsed: Bool = false

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
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
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

                        // Show BERT NER section if there are BERT findings
                        if !viewModel.bertNERFindings.isEmpty {
                            EntityTypeSection(
                                title: "BERT NER Findings",
                                icon: "text.viewfinder",
                                color: .cyan,
                                entities: viewModel.bertNERFindings,
                                viewModel: viewModel,
                                isAISection: true  // Reuse AI section styling
                            )
                        }

                        // Show XLM-R NER section if there are XLM-R findings
                        if !viewModel.xlmrNERFindings.isEmpty {
                            EntityTypeSection(
                                title: "XLM-R NER Findings",
                                icon: "globe.americas.fill",
                                color: .teal,
                                entities: viewModel.xlmrNERFindings,
                                viewModel: viewModel,
                                isAISection: true  // Reuse AI section styling
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
                                isAISection: true  // Reuse AI section styling
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

    // MARK: - Grouping Helpers

    /// Entity types in display order (excluding AI findings which are shown separately)
    private var groupedEntityTypes: [EntityType] {
        [.personClient, .personProvider, .personOther, .date, .location, .organization, .contact, .identifier, .numericAll]
    }

    /// Get entities for a specific type (excluding AI, BERT, and XLM-R findings to avoid duplicates)
    private func entitiesForType(_ type: EntityType) -> [Entity] {
        let aiIds = Set(viewModel.piiReviewFindings.map { $0.id })
        let bertIds = Set(viewModel.bertNERFindings.map { $0.id })
        let xlmrIds = Set(viewModel.xlmrNERFindings.map { $0.id })
        return viewModel.allEntities.filter { $0.type == type && !aiIds.contains($0.id) && !bertIds.contains($0.id) && !xlmrIds.contains($0.id) }
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

                // Expand/collapse button for rest of header
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(color)
                            .frame(width: 14)

                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(color)

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
            }
            .padding(.vertical, 6)
            .padding(.horizontal, DesignSystem.Spacing.xs)
            .background(color.opacity(0.08))
            .cornerRadius(4)

            // Entity rows
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(entities) { entity in
                        RedactEntityRow(
                            entity: entity,
                            isExcluded: viewModel.isEntityExcluded(entity),
                            isFromAIReview: isAISection,
                            onToggle: { viewModel.toggleEntity(entity) }
                        )
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
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Button(action: onToggle) {
                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                    .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : entity.type.highlightColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entity.originalText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
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

                Text("→ \(entity.replacementCode)")
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isExcluded ? Color.clear : (isFromAIReview ? Color.orange.opacity(0.1) : entity.type.highlightColor.opacity(0.1)))
        )
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

// MARK: - Preview

#if DEBUG
struct RedactPhaseView_Previews: PreviewProvider {
    static var previews: some View {
        RedactPhaseView(viewModel: WorkflowViewModel())
            .frame(width: 900, height: 600)
    }
}
#endif
