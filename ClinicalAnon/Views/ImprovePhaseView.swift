//
//  ImprovePhaseView.swift
//  Redactor
//
//  Purpose: Second phase - AI processing with document type selection
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Improve Phase View

/// Phase 2: Send redacted text to AI for processing
struct ImprovePhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @ObservedObject var documentTypeManager: DocumentTypeManager = .shared

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Document type selector (flat chips)
            documentTypeSelector

            Divider().opacity(0.3)

            // Two-pane content: Redacted Input | AI Output
            HStack(spacing: 0) {
                redactedInputPane
                aiOutputPane
            }
        }
        .sheet(isPresented: $viewModel.showPromptEditor) {
            if let docType = viewModel.documentTypeToEdit {
                PromptEditorSheet(
                    documentType: docType,
                    documentTypeManager: documentTypeManager,
                    onDismiss: { viewModel.showPromptEditor = false }
                )
            }
        }
        .sheet(isPresented: $viewModel.showAddCustomCategory) {
            AddCustomCategorySheet(
                documentTypeManager: documentTypeManager,
                onDismiss: { viewModel.showAddCustomCategory = false }
            )
        }
    }

    // MARK: - Document Type Selector

    private var documentTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.small) {
                // All document type chips
                ForEach(documentTypeManager.documentTypes) { docType in
                    DocumentTypeChip(
                        documentType: docType,
                        isSelected: viewModel.selectedDocumentType?.id == docType.id,
                        onSelect: { viewModel.selectedDocumentType = docType },
                        onEdit: { viewModel.editPrompt(for: docType) }
                    )
                }

                // Add Custom button
                AddCategoryButton(onTap: { viewModel.openAddCustomCategory() })
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Redacted Input Pane

    private var redactedInputPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Redacted Input")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("Read-only")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            ScrollView {
                if let cachedRedacted = viewModel.cachedRedactedAttributed {
                    Text(cachedRedacted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                } else {
                    Text(viewModel.displayedRedactedText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Process button
            Divider().opacity(0.15)

            HStack {
                Button("← Back") {
                    viewModel.goToPreviousPhase()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button(action: { viewModel.processWithAI() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        if let docType = viewModel.selectedDocumentType {
                            Image(systemName: docType.icon)
                            Text(docType.name)
                        } else {
                            Text("Select a type")
                        }
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.displayedRedactedText.isEmpty || viewModel.isAIProcessing || viewModel.selectedDocumentType == nil)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - AI Output Pane

    private var aiOutputPane: some View {
        VStack(spacing: 0) {
            // Header with Redo button
            HStack {
                Text("AI Output")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if viewModel.isAIProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }

                Spacer()

                if !viewModel.aiOutput.isEmpty && !viewModel.isAIProcessing {
                    Button(action: { viewModel.regenerateAIOutput() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Redo")
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if viewModel.isAIProcessing {
                    Button("Cancel") {
                        viewModel.cancelAIRequest()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if viewModel.isAIProcessing && viewModel.aiOutput.isEmpty {
                // Loading skeleton
                SkeletonTextView()
            } else if let error = viewModel.aiError {
                // Error state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.error)

                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        viewModel.dismissError()
                        viewModel.processWithAI()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.aiOutput.isEmpty {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

                    Text("AI output will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    if let docType = viewModel.selectedDocumentType {
                        Text("Click \"\(docType.name)\" to process")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    } else {
                        Text("Select a document type to get started")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // AI output content
                ScrollView {
                    Text(viewModel.aiOutput)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Continue button
            if !viewModel.aiOutput.isEmpty && !viewModel.isAIProcessing {
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

// MARK: - Document Type Chip

private struct DocumentTypeChip: View {

    let documentType: DocumentType
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: documentType.icon)
                    .font(.system(size: 12))

                Text(documentType.name)
                    .font(DesignSystem.Typography.caption)

                // Edit button (visible on hover or when selected)
                if isHovering || isSelected {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                Capsule()
                    .fill(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.surface)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Add Category Button

private struct AddCategoryButton: View {

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 12))

                Text("Add")
                    .font(DesignSystem.Typography.caption)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                Capsule()
                    .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(DesignSystem.Colors.textSecondary)
    }
}

// MARK: - Skeleton Text View

private struct SkeletonTextView: View {

    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.15))
                    .frame(height: 16)
                    .frame(maxWidth: index == 7 ? 200 : .infinity)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.medium)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {

    let documentType: DocumentType
    @ObservedObject var documentTypeManager: DocumentTypeManager
    let onDismiss: () -> Void

    @State private var editedPrompt: String = ""
    @State private var hasChanges: Bool = false

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header
            HStack {
                Image(systemName: documentType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Edit \(documentType.name) Prompt")
                    .font(DesignSystem.Typography.heading)

                Spacer()

                if documentType.isBuiltIn && documentTypeManager.hasCustomPrompt(typeId: documentType.id) {
                    Button("Reset to Default") {
                        documentTypeManager.resetToDefault(typeId: documentType.id)
                        editedPrompt = DocumentType.defaultPrompt(for: documentType.id) ?? ""
                        hasChanges = false
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }

            Text("This prompt is sent to the AI along with your redacted text.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            // Prompt editor
            TextEditor(text: $editedPrompt)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 250)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: editedPrompt) { _ in
                    hasChanges = editedPrompt != documentType.prompt
                }

            // Buttons
            HStack {
                if !documentType.isBuiltIn {
                    Button("Delete") {
                        documentTypeManager.deleteCustomType(documentType)
                        onDismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.error)
                }

                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Save") {
                    documentTypeManager.updatePrompt(for: documentType.id, newPrompt: editedPrompt)
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasChanges)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 600, height: 450)
        .onAppear {
            editedPrompt = documentType.prompt
        }
    }
}

// MARK: - Add Custom Category Sheet

struct AddCustomCategorySheet: View {

    @ObservedObject var documentTypeManager: DocumentTypeManager
    let onDismiss: () -> Void

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var selectedIcon: String = "doc.text"

    private let availableIcons = [
        "doc.text", "doc.richtext", "clipboard", "list.bullet", "text.alignleft",
        "person.text.rectangle", "heart.text.square", "brain", "cross.case"
    ]

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("New Document Type")
                .font(DesignSystem.Typography.heading)

            // Name field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Name")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                TextField("e.g., Case Summary", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon picker
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Icon")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Spacing.small) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedIcon == icon ? DesignSystem.Colors.primaryTeal.opacity(0.2) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedIcon == icon ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textPrimary)
                    }
                }
            }

            // Prompt field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Prompt")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                    )

                Text("Describe what the AI should do with the text. The redacted text will be sent along with this prompt.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Create") {
                    documentTypeManager.addCustomType(name: name, prompt: prompt, icon: selectedIcon)
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 500, height: 500)
    }
}

// MARK: - Preview

#if DEBUG
struct ImprovePhaseView_Previews: PreviewProvider {
    static var previews: some View {
        ImprovePhaseView(viewModel: {
            let vm = WorkflowViewModel()
            vm.currentPhase = .improve
            return vm
        }())
        .frame(width: 900, height: 600)
    }
}
#endif
