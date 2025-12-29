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

            // Two-pane content: Original | Redacted
            HStack(spacing: 0) {
                // LEFT: Original Text
                originalTextPane

                // RIGHT: Redacted Text
                redactedTextPane
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
                    Text("\(viewModel.inputText.split(separator: " ").count) words")
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
                InteractiveTextView(
                    attributedText: cachedOriginal,
                    onDoubleClick: { word in
                        viewModel.openAddCustomEntity(withText: word)
                    }
                )
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
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
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

            // Continue button at bottom
            if viewModel.result != nil {
                Divider().opacity(0.15)

                HStack {
                    Spacer()

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
                .padding(DesignSystem.Spacing.medium)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
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

                // Entity list
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(viewModel.allEntities) { entity in
                            RedactEntityRow(
                                entity: entity,
                                isExcluded: viewModel.isEntityExcluded(entity),
                                onToggle: { viewModel.toggleEntity(entity) }
                            )
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
        .frame(width: isCollapsed ? 40 : 180)
        .background(DesignSystem.Colors.surface)
        .animation(.easeInOut(duration: 0.2), value: isCollapsed)
    }
}

// MARK: - Entity Row

private struct RedactEntityRow: View {

    let entity: Entity
    let isExcluded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Button(action: onToggle) {
                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                    .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : entity.type.highlightColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.originalText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(isExcluded ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .strikethrough(isExcluded)

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
                .fill(isExcluded ? Color.clear : entity.type.highlightColor.opacity(0.1))
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
