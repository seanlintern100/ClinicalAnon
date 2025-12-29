//
//  ImprovePhaseView.swift
//  Redactor
//
//  Purpose: Second phase - AI processing with document type selection and refinement
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Improve Phase View

/// Phase 2: Send redacted text to AI for processing, then refine iteratively
struct ImprovePhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @ObservedObject var documentTypeManager: DocumentTypeManager = .shared

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Document type selector and custom instructions
            if !viewModel.isInRefinementMode {
                documentTypeSelector
                customInstructionsField
            } else {
                refinementHeader
            }

            Divider().opacity(0.3)

            // Two-pane content
            HStack(spacing: 0) {
                if viewModel.isInRefinementMode {
                    // Refinement mode: Current output | Chat
                    currentOutputPane
                    refinementChatPane
                } else {
                    // Initial mode: Redacted input | AI output
                    redactedInputPane
                    aiOutputPane
                }
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
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
        }
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Custom Instructions Field

    private var customInstructionsField: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text("Additional instructions")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("(optional)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            }

            TextField("e.g., Keep under 500 words, include medication list...", text: $viewModel.customInstructions)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.CornerRadius.small)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .stroke(DesignSystem.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.bottom, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Refinement Header

    private var refinementHeader: some View {
        HStack {
            Button(action: { viewModel.exitRefinementMode() }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrow.left")
                    Text("Back to Input")
                }
                .font(DesignSystem.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(DesignSystem.Colors.textSecondary)

            Spacer()

            if let docType = viewModel.selectedDocumentType {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: docType.icon)
                    Text(docType.name)
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.small)
            }

            Spacer()

            Text("Refinement Mode")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Redacted Input Pane (Initial Mode)

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

    // MARK: - AI Output Pane (Initial Mode)

    private var aiOutputPane: some View {
        VStack(spacing: 0) {
            // Header
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
                SkeletonTextView()
            } else if let error = viewModel.aiError {
                errorView(error)
            } else if viewModel.aiOutput.isEmpty {
                emptyStateView
            } else {
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
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Current Output Pane (Refinement Mode)

    private var currentOutputPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Current Output")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if viewModel.isAIProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }

                Spacer()

                if !viewModel.isAIProcessing {
                    Button(action: { viewModel.regenerateAIOutput() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Start Over")
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            ScrollView {
                Text(viewModel.aiOutput)
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.medium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Continue button
            Divider().opacity(0.15)

            HStack {
                Spacer()

                Button(action: { viewModel.continueToNextPhase() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Accept & Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isAIProcessing)
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

    // MARK: - Refinement Chat Pane

    private var refinementChatPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Refine")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("Chat to make changes")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Chat history
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        ForEach(Array(viewModel.chatHistory.enumerated()), id: \.offset) { index, message in
                            ChatMessageView(role: message.role, content: message.content)
                                .id(index)
                        }

                        if viewModel.isAIProcessing {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Generating...")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .padding(.leading, DesignSystem.Spacing.medium)
                        }
                    }
                    .padding(DesignSystem.Spacing.medium)
                }
                .onChange(of: viewModel.chatHistory.count) { _ in
                    withAnimation {
                        proxy.scrollTo(viewModel.chatHistory.count - 1, anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.15)

            // Input field
            HStack(spacing: DesignSystem.Spacing.small) {
                TextField("Ask for changes...", text: $viewModel.refinementInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.background)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                    .onSubmit {
                        viewModel.sendRefinement()
                    }

                Button(action: { viewModel.sendRefinement() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(viewModel.refinementInput.isEmpty || viewModel.isAIProcessing
                            ? DesignSystem.Colors.textSecondary.opacity(0.3)
                            : DesignSystem.Colors.primaryTeal)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.refinementInput.isEmpty || viewModel.isAIProcessing)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 300, idealWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helper Views

    private func errorView(_ error: String) -> some View {
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
    }

    private var emptyStateView: some View {
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
    }
}

// MARK: - Chat Message View

private struct ChatMessageView: View {
    let role: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(role == "user" ? "You" : "AI")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
                .foregroundColor(role == "user" ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)

            Text(content)
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(role == "assistant" ? 5 : nil)  // Truncate AI responses in chat
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(role == "user"
                    ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                    : DesignSystem.Colors.background)
        )
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

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Name")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                TextField("e.g., Case Summary", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

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

                Text("Describe what the AI should do with the text.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

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
