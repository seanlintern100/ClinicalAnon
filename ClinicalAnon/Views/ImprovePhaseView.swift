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
    @State private var showAddAnalysisSheet: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header: Document type selector + Start Over
            headerBar

            Divider().opacity(0.3)

            // Content: Sources sidebar (if multiple docs) | Document | Chat
            HStack(spacing: 0) {
                // Only show sidebar if multiple source docs
                if viewModel.improveState.sourceDocuments.count > 1 {
                    sourceDocumentsSidebar
                    Divider().opacity(0.3)
                }
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
        .sheet(isPresented: $showAddAnalysisSheet) {
            AddAnalysisTypeSheet(
                documentTypeManager: documentTypeManager,
                onDismiss: { showAddAnalysisSheet = false },
                onCreated: { newType in
                    viewModel.selectedDocumentType = newType
                    viewModel.sliderSettings = newType.defaultSliders
                    showAddAnalysisSheet = false
                }
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Document type chips (Notes, Report, Custom, + user-created)
            ForEach(documentTypeManager.documentTypes) { docType in
                DocumentTypeChip(
                    documentType: docType,
                    isSelected: viewModel.selectedDocumentType?.id == docType.id,
                    isDisabled: viewModel.hasGeneratedOutput,
                    onSelect: {
                        viewModel.selectedDocumentType = docType
                        // Load saved sliders for this type
                        viewModel.sliderSettings = documentTypeManager.getSliders(for: docType.id)
                        // Load custom instructions for Custom type
                        if docType.id == DocumentType.custom.id {
                            viewModel.customInstructions = documentTypeManager.getCustomInstructions(for: docType.id)
                        }
                    },
                    onEdit: { viewModel.editPrompt(for: docType) },
                    onDelete: docType.isUserCreated ? {
                        // Clear selection if deleting selected type
                        if viewModel.selectedDocumentType?.id == docType.id {
                            viewModel.selectedDocumentType = documentTypeManager.documentTypes.first
                        }
                        documentTypeManager.deleteAnalysisType(id: docType.id)
                    } : nil
                )
            }

            // Add new analysis type button
            if !viewModel.hasGeneratedOutput {
                Button(action: { showAddAnalysisSheet = true }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Add new analysis type")
            }

            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
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

                if !viewModel.currentDocument.isEmpty {
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
            if viewModel.currentDocument.isEmpty && !(viewModel.isAIProcessing && viewModel.streamingDestination == .document) {
                // Empty state (unless actively streaming a document)
                documentEmptyState
            } else if let error = viewModel.aiError {
                // Error state
                errorView(error)
            } else {
                // Document content - only show streaming if destination is document
                ScrollView {
                    if viewModel.isAIProcessing && viewModel.streamingDestination == .document {
                        // Streaming a document update
                        MarkdownText(viewModel.aiOutput)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.medium)
                    } else {
                        // Show stable document with change highlighting
                        HighlightedDocument(
                            text: viewModel.currentDocument,
                            changedLineIndices: viewModel.changedLineIndices
                        )
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                    }
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

    // MARK: - Source Documents Sidebar

    private var sourceDocumentsSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sources (\(viewModel.improveState.sourceDocuments.count))")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Document list
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.small) {
                    ForEach(viewModel.improveState.sourceDocuments) { doc in
                        SourceDocumentRow(
                            document: doc,
                            isSelected: viewModel.improveState.selectedDocumentId == doc.id,
                            onSelect: { viewModel.improveState.selectedDocumentId = doc.id },
                            onUpdateDescription: { desc in
                                viewModel.updateSourceDocumentDescription(id: doc.id, description: desc)
                            }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.small)
            }

            // Preview of selected document
            if let selected = viewModel.improveState.selectedDocument {
                Divider().opacity(0.15)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Preview")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    ScrollView {
                        Text(selected.redactedText)
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                }
                .padding(DesignSystem.Spacing.small)
            }
        }
        .frame(width: 220)
        .background(DesignSystem.Colors.surface)
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

                    // Show streaming conversation response in chat
                    if viewModel.isAIProcessing && viewModel.streamingDestination == .chat {
                        ChatMessageView(
                            role: "assistant",
                            content: viewModel.aiOutput,
                            isLatest: true,
                            isFirstMessage: false
                        )
                        .id("streaming")
                    }

                    // Show status indicator while processing
                    if viewModel.isAIProcessing {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(viewModel.streamingDestination == .chat ? "Thinking..." : "Updating document...")
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
                .disabled(
                    (viewModel.displayedRedactedText.isEmpty && viewModel.improveState.sourceDocuments.isEmpty)
                    || viewModel.selectedDocumentType == nil
                )
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
        viewModel.copyCurrentDocument()
    }
}

// MARK: - Chat Message View

private struct ChatMessageView: View {
    let role: String
    let content: String
    var isLatest: Bool = false
    var isFirstMessage: Bool = false

    private var isUser: Bool { role == "user" }
    private var isDocumentUpdate: Bool { content == "[[DOCUMENT_UPDATED]]" }

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
                    if isFirstMessage || isDocumentUpdate {
                        // Document update: show status with icon
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: isFirstMessage ? "doc.text.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.Colors.primaryTeal)

                            Text(isFirstMessage ? "Document generated" : "Document updated")
                                .font(.system(size: 13))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    } else {
                        // Conversational response: show with markdown formatting
                        MarkdownText(content)
                            .textSelection(.enabled)
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

// MARK: - Source Document Row

private struct SourceDocumentRow: View {
    let document: SourceDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdateDescription: (String) -> Void

    @State private var isEditingDescription: Bool = false
    @State private var editedDescription: String = ""

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : DesignSystem.Colors.primaryTeal)

                    Text(document.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)

                    Spacer()

                    // Edit description button
                    Button(action: {
                        editedDescription = document.description
                        isEditingDescription = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isSelected ? .white.opacity(0.7) : DesignSystem.Colors.textSecondary)
                }

                if !document.description.isEmpty {
                    Text(document.description)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }

                Text("\(document.entities.count) entities")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .white.opacity(0.6) : DesignSystem.Colors.textSecondary.opacity(0.7))
            }
            .padding(DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.background)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isEditingDescription) {
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("Document Description")
                    .font(DesignSystem.Typography.subheading)

                TextField("Brief description...", text: $editedDescription)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack {
                    Button("Cancel") { isEditingDescription = false }
                        .buttonStyle(SecondaryButtonStyle())

                    Button("Save") {
                        onUpdateDescription(editedDescription)
                        isEditingDescription = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding()
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
        // Use custom MarkdownParser for proper heading support (## headers)
        Text(MarkdownParser.parseToAttributedString(text))
            .foregroundColor(DesignSystem.Colors.textPrimary)
    }
}

// MARK: - Highlighted Document View

private struct HighlightedDocument: View {
    let text: String
    let changedLineIndices: Set<Int>

    // Pre-compute lines once
    private var lines: [(index: Int, content: String)] {
        text.components(separatedBy: .newlines).enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.index) { index, line in
                HighlightedLine(
                    line: line,
                    isChanged: changedLineIndices.contains(index)
                )
            }
        }
    }
}

// Separate view for each line to minimize re-renders
private struct HighlightedLine: View {
    let line: String
    let isChanged: Bool

    var body: some View {
        // Use custom MarkdownParser to handle headers (##) and inline formatting
        Text(MarkdownParser.parseToAttributedString(line.isEmpty ? " " : line))
        .foregroundColor(DesignSystem.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            isChanged
                ? DesignSystem.Colors.primaryTeal.opacity(0.15)
                : Color.clear
        )
        .cornerRadius(2)
    }
}

// MARK: - Document Type Chip

private struct DocumentTypeChip: View {

    let documentType: DocumentType
    let isSelected: Bool
    var isDisabled: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    var onDelete: (() -> Void)? = nil  // Only for user-created types

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

                    // Delete button for user-created types
                    if let deleteAction = onDelete {
                        Button(action: deleteAction) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : DesignSystem.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
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

// MARK: - Slider Control

private struct SliderControl: View {
    let label: String
    @Binding var value: Int
    let texts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()

                Text("\(value)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0) }
                ),
                in: 1...5,
                step: 1
            )
            .tint(DesignSystem.Colors.primaryTeal)

            Text(texts[max(0, min(value - 1, 4))])
                .font(.system(size: 10))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Prompt Editor Sheet

struct PromptEditorSheet: View {

    let documentType: DocumentType
    @ObservedObject var documentTypeManager: DocumentTypeManager
    let onDismiss: () -> Void

    @State private var editedPrompt: String = ""
    @State private var editedSliders: SliderSettings = SliderSettings()
    @State private var editedCustomInstructions: String = ""
    @State private var hasChanges: Bool = false

    private var isCustomType: Bool {
        documentType.id == DocumentType.custom.id
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Header
            HStack {
                Image(systemName: documentType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Edit \(documentType.name) Settings")
                    .font(DesignSystem.Typography.heading)

                Spacer()

                if documentType.isBuiltIn && documentTypeManager.hasCustomPrompt(typeId: documentType.id) {
                    Button("Reset to Default") {
                        documentTypeManager.resetPromptTemplate(for: documentType.id)
                        documentTypeManager.resetSliders(for: documentType.id)
                        // Strip style block for display
                        let defaultTemplate = DocumentType.defaultPromptTemplate(for: documentType.id) ?? ""
                        editedPrompt = DocumentType.stripStyleBlock(from: defaultTemplate)
                        editedSliders = DocumentType.defaultSliders(for: documentType.id) ?? SliderSettings()
                        hasChanges = false
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }

            // Sliders section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Style Settings")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.large) {
                    SliderControl(
                        label: "Formality",
                        value: $editedSliders.formality,
                        texts: SliderSettings.formalityTexts
                    )

                    SliderControl(
                        label: "Detail",
                        value: $editedSliders.detail,
                        texts: SliderSettings.detailTexts
                    )

                    SliderControl(
                        label: "Structure",
                        value: $editedSliders.structure,
                        texts: SliderSettings.structureTexts
                    )
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.small)

            // Custom instructions (only for Custom type)
            if isCustomType {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Custom Instructions")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    TextField("Describe what you want the AI to do...", text: $editedCustomInstructions)
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
            }

            // Prompt template section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Prompt Template")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                TextEditor(text: $editedPrompt)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.small)
                    .background(Color(NSColor.textBackgroundColor))
                    .frame(minHeight: 250, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .frame(maxHeight: .infinity)

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Save") {
                    // Re-inject style block before saving (it was stripped for display)
                    let fullTemplate = DocumentType.injectStyleBlock(into: editedPrompt)
                    documentTypeManager.updatePromptTemplate(for: documentType.id, newTemplate: fullTemplate)
                    documentTypeManager.updateSliders(for: documentType.id, sliders: editedSliders)
                    if isCustomType {
                        documentTypeManager.updateCustomInstructions(for: documentType.id, instructions: editedCustomInstructions)
                    }
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(minWidth: 700, maxWidth: 700, minHeight: isCustomType ? 700 : 650, maxHeight: 900)
        .onAppear {
            // Strip style block for display - it's controlled by sliders above
            editedPrompt = DocumentType.stripStyleBlock(from: documentType.promptTemplate)
            editedSliders = documentTypeManager.getSliders(for: documentType.id)
            editedCustomInstructions = documentTypeManager.getCustomInstructions(for: documentType.id)
        }
        .onChange(of: editedPrompt) { _ in updateHasChanges() }
        .onChange(of: editedSliders) { _ in updateHasChanges() }
        .onChange(of: editedCustomInstructions) { _ in updateHasChanges() }
    }

    private func updateHasChanges() {
        let originalSliders = documentTypeManager.getSliders(for: documentType.id)
        let originalCustomInstructions = documentTypeManager.getCustomInstructions(for: documentType.id)
        let strippedOriginal = DocumentType.stripStyleBlock(from: documentType.promptTemplate)
        hasChanges = editedPrompt != strippedOriginal ||
                     editedSliders != originalSliders ||
                     (isCustomType && editedCustomInstructions != originalCustomInstructions)
    }
}

// MARK: - Add Analysis Type Sheet

struct AddAnalysisTypeSheet: View {

    @ObservedObject var documentTypeManager: DocumentTypeManager
    let onDismiss: () -> Void
    let onCreated: (DocumentType) -> Void

    @State private var name: String = ""
    @State private var sliders: SliderSettings = SliderSettings()
    // Style block is hidden from editor - controlled by sliders above
    @State private var promptTemplate: String = """
        You are a clinical writing assistant.

        [Your instructions here]

        Placeholders like [PERSON_A], [DATE_A] must be preserved exactly.
        Use only information provided — do not invent details.
        Respond with only the requested content.
        """

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("New Analysis Type")
                    .font(DesignSystem.Typography.heading)

                Spacer()
            }

            // Name field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Name")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                TextField("e.g., Progress Note, Assessment Report", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.background)
                    .cornerRadius(DesignSystem.CornerRadius.small)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .stroke(DesignSystem.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                    )
            }

            // Sliders section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Style Settings")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.large) {
                    SliderControl(
                        label: "Formality",
                        value: $sliders.formality,
                        texts: SliderSettings.formalityTexts
                    )

                    SliderControl(
                        label: "Detail",
                        value: $sliders.detail,
                        texts: SliderSettings.detailTexts
                    )

                    SliderControl(
                        label: "Structure",
                        value: $sliders.structure,
                        texts: SliderSettings.structureTexts
                    )
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.small)

            // Prompt template section
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Prompt Template")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                TextEditor(text: $promptTemplate)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.small)
                    .background(Color(NSColor.textBackgroundColor))
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .frame(maxHeight: .infinity)

            // Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Create") {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Re-inject style block before saving (it was hidden from editor)
                    let fullTemplate = DocumentType.injectStyleBlock(into: promptTemplate)
                    let newType = documentTypeManager.createAnalysisType(
                        name: trimmedName,
                        promptTemplate: fullTemplate,
                        sliders: sliders
                    )
                    onCreated(newType)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(minWidth: 700, maxWidth: 700, minHeight: 650, maxHeight: 900)
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
