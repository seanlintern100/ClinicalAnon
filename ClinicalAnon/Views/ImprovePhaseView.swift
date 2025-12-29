//
//  ImprovePhaseView.swift
//  Redactor
//
//  Purpose: Second phase - AI processing with artifact-style document + chat
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Improve Phase View

/// Phase 2: Artifact-style layout with document on left, chat on right
struct ImprovePhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @ObservedObject var documentTypeManager: DocumentTypeManager = .shared

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header: Document type selector + Start Over
            headerBar

            // Custom instructions field
            customInstructionsField

            Divider().opacity(0.3)

            // Two-pane content: Document | Chat
            HStack(spacing: 0) {
                documentPane
                chatPane
            }

            Divider().opacity(0.3)

            // Footer with navigation
            footerBar
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

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    // All document type chips
                    ForEach(documentTypeManager.documentTypes) { docType in
                        DocumentTypeChip(
                            documentType: docType,
                            isSelected: viewModel.selectedDocumentType?.id == docType.id,
                            isDisabled: viewModel.hasGeneratedOutput,
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

            // Start Over button (only when output exists)
            if viewModel.hasGeneratedOutput {
                Divider()
                    .frame(height: 24)
                    .opacity(0.3)
                    .padding(.horizontal, DesignSystem.Spacing.small)

                Button(action: { viewModel.startOverAI() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text("Start Over")
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.trailing, DesignSystem.Spacing.medium)
            }
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
                .disabled(viewModel.hasGeneratedOutput)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.bottom, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Document Pane (Left)

    private var documentPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Document")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if viewModel.isAIProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }

                Spacer()

                if !viewModel.aiOutput.isEmpty {
                    Button(action: { copyDocument() }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .help("Copy document")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Document content
            if viewModel.aiOutput.isEmpty && !viewModel.isAIProcessing {
                // Empty state
                documentEmptyState
            } else if let error = viewModel.aiError {
                // Error state
                errorView(error)
            } else {
                // Document content (streams in real-time) with markdown
                ScrollView {
                    MarkdownText(viewModel.aiOutput)
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
        .frame(minWidth: 350, idealWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat Pane (Right)

    private var chatPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chat")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                if viewModel.hasGeneratedOutput {
                    Text("Ask for changes")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .frame(height: 44)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Chat content
            if !viewModel.hasGeneratedOutput && !viewModel.isAIProcessing {
                // Empty state
                chatEmptyState
            } else {
                // Chat history
                chatHistory

                // Input field (only after first generation)
                if viewModel.hasGeneratedOutput {
                    chatInputBar
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 280, idealWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat History

    private var chatHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    ForEach(Array(viewModel.chatHistory.enumerated()), id: \.offset) { index, message in
                        ChatMessageView(
                            role: message.role,
                            content: message.content,
                            isLatest: index == viewModel.chatHistory.count - 1,
                            isFirstMessage: index == 0
                        )
                        .id(index)
                    }

                    // Show generating indicator
                    if viewModel.isAIProcessing {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Updating document...")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        .padding(.leading, DesignSystem.Spacing.medium)
                        .id("generating")
                    }
                }
                .padding(DesignSystem.Spacing.medium)
            }
            .onChange(of: viewModel.chatHistory.count) { _ in
                withAnimation {
                    proxy.scrollTo(viewModel.chatHistory.count - 1, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isAIProcessing) { isProcessing in
                if isProcessing {
                    withAnimation {
                        proxy.scrollTo("generating", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chat Input Bar

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)

            HStack(spacing: DesignSystem.Spacing.small) {
                TextField("Ask for changes...", text: $viewModel.refinementInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.background)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                    .onSubmit {
                        viewModel.sendRefinement()
                    }

                Button(action: { viewModel.sendRefinement() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(viewModel.refinementInput.isEmpty || viewModel.isAIProcessing
                            ? DesignSystem.Colors.textSecondary.opacity(0.3)
                            : DesignSystem.Colors.primaryTeal)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.refinementInput.isEmpty || viewModel.isAIProcessing)
            }
            .padding(DesignSystem.Spacing.small)
        }
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button("← Back") {
                viewModel.goToPreviousPhase()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            if viewModel.isAIProcessing {
                Button("Cancel") {
                    viewModel.cancelAIRequest()
                }
                .buttonStyle(SecondaryButtonStyle())
            } else if !viewModel.hasGeneratedOutput {
                // Generate button
                Button(action: { viewModel.processWithAI() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        if let docType = viewModel.selectedDocumentType {
                            Image(systemName: docType.icon)
                            Text("Generate \(docType.name)")
                        } else {
                            Text("Select a type")
                        }
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.displayedRedactedText.isEmpty || viewModel.selectedDocumentType == nil)
            } else {
                // Continue button
                Button(action: { viewModel.continueToNextPhase() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Text("Accept & Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Empty States

    private var documentEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

            if let docType = viewModel.selectedDocumentType {
                Text("Your \(docType.name.lowercased()) will appear here")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            } else {
                Text("Select a document type to get started")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

            Text("Generate a document to start refining")
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(DesignSystem.Colors.error)

            Text(error)
                .font(.system(size: 13))
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

    // MARK: - Actions

    private func copyDocument() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(viewModel.aiOutput, forType: .string)
    }
}

// MARK: - Chat Message View

private struct ChatMessageView: View {
    let role: String
    let content: String
    var isLatest: Bool = false
    var isFirstMessage: Bool = false

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 40)  // Push user messages to right
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: DesignSystem.Spacing.xs) {
                Text(isUser ? "You" : "AI")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isUser ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)

                if role == "assistant" {
                    // AI messages: show status message (full document is in left pane)
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: isFirstMessage ? "doc.text.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text(isFirstMessage ? "Document generated — see left pane" : "Document updated — see left pane")
                            .font(.system(size: 13))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                } else {
                    // User messages: show full content
                    Text(content)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(isUser
                        ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                        : DesignSystem.Colors.background)
            )

            if !isUser {
                Spacer(minLength: 40)  // Push AI messages to left
            }
        }
    }
}

// MARK: - Markdown Text View

private struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.Colors.textPrimary)
        } else {
            // Fallback to plain text if markdown parsing fails
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

// MARK: - Document Type Chip

private struct DocumentTypeChip: View {

    let documentType: DocumentType
    let isSelected: Bool
    var isDisabled: Bool = false
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

                if (isHovering || isSelected) && !isDisabled {
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
        .opacity(isDisabled && !isSelected ? 0.5 : 1.0)
        .disabled(isDisabled)
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
