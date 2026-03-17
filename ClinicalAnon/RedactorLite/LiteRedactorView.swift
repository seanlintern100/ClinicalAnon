//
//  LiteRedactorView.swift
//  Redactor Lite
//
//  Purpose: Three-panel redaction interface — Input | Redacted | Paste Back/Restored
//           With entity sidebar and multi-document support.
//  Organization: 3 Big Things
//

import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Lite Redactor View

struct LiteRedactorView: View {

    @ObservedObject var viewModel: LiteViewModel
    @State private var showNewSessionAlert: Bool = false
    @State private var showPendingChangesAlert: Bool = false
    @State private var isDropTargeted: Bool = false
    /// nil = show current document, UUID = show a saved source document
    @State private var selectedDocId: UUID? = nil
    /// Shared max header height across all 3 panels
    @State private var maxHeaderHeight: CGFloat = 0

    var body: some View {
        ZStack {
            // Portal-inspired gradient background
            GradientPageBackground()

            VStack(spacing: 0) {
                // Toolbar
                toolbar

                // Main content: [Entity Sidebar] | Panel 1 | Panel 2 | Panel 3
                HStack(spacing: DesignSystem.Spacing.medium) {
                    // Entity sidebar (appears after analysis)
                    if viewModel.result != nil || !viewModel.sourceDocuments.isEmpty {
                        entitySidebar
                    }

                    // Panel 1: Input
                    inputPanel
                        .frame(maxWidth: .infinity)
                        .glassPanel()

                    // Panel 2: Redacted text
                    redactedPanel
                        .frame(maxWidth: .infinity)
                        .glassPanel()

                    // Panel 3: Paste back / Restored
                    restorePanel
                        .frame(maxWidth: .infinity)
                        .glassPanel()
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.bottom, DesignSystem.Spacing.medium)
                .padding(.top, DesignSystem.Spacing.small)
            }
        }
        .onPreferenceChange(HeaderHeightKey.self) { maxHeaderHeight = $0 }
        .sheet(isPresented: $viewModel.showingAddCustomEntity) {
            AddCustomEntitySheet(
                prefilledText: viewModel.prefilledEntityText,
                onAdd: { text, type in viewModel.addCustomEntity(text: text, type: type) }
            )
        }
        .sheet(isPresented: $viewModel.redactState.showDuplicateFinderModal, onDismiss: {
            // After duplicate finder closes (merged or skipped), suggest client
            viewModel.identifyClientCandidates()
        }) {
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
        .sheet(isPresented: $viewModel.showClientSuggestion) {
            ClientSuggestionModal(
                suggestedClient: viewModel.suggestedClientEntity,
                candidates: viewModel.clientSuggestionCandidates,
                onConfirm: { viewModel.confirmClientSelection($0) },
                onDismiss: { viewModel.dismissClientSuggestion() }
            )
        }
        .alert("Start New Session?", isPresented: $showNewSessionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { viewModel.startNewSession() }
        } message: {
            Text("This will clear all documents, entities, and pasted text. This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    // MARK: - Action Buttons (+ Doc / Analyse)

    /// Compact action buttons that stay on one line; wraps vertically only if truly no room
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            // First try: both buttons side by side
            HStack(spacing: DesignSystem.Spacing.small) {
                addDocButton
                analyzeButton
            }
            // Fallback: stack vertically
            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.xs) {
                addDocButton
                analyzeButton
            }
        }
    }

    @ViewBuilder
    private var addDocButton: some View {
        if viewModel.result != nil {
            Button(action: { viewModel.addAnotherDocument() }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "plus.doc")
                        .frame(width: 14, height: 14)
                    Text("+ Doc")
                }
                .font(DesignSystem.Typography.caption)
                .lineLimit(1)
                .fixedSize()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var analyzeButton: some View {
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
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(DesignSystem.Typography.caption)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.inputText.isEmpty || viewModel.isProcessing)
    }

    private var toolbar: some View {
        HStack {
            // Start Recording button
            Button(action: {
                RecordingWindowController.shared.showRecordingWindow()
            }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                    Text("Record Session")
                }
                .font(DesignSystem.Typography.caption)
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            // Document count indicator
            if !viewModel.sourceDocuments.isEmpty {
                let count = viewModel.sourceDocuments.count + (viewModel.result != nil ? 1 : 0)
                Text("\(count) document\(count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Button(action: {
                if viewModel.hasAnyContent {
                    showNewSessionAlert = true
                } else {
                    viewModel.startNewSession()
                }
            }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("New Session")
                }
                .font(DesignSystem.Typography.caption)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
    }

    // MARK: - Panel 1: Input

    private var inputPanel: some View {
        VStack(spacing: 0) {
            // Header area — measured and synced across panels
            VStack(spacing: 0) {
                HStack {
                    Text("Source Text")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    if !viewModel.inputText.isEmpty {
                        Text("\(viewModel.inputText.split(separator: " ").count) words")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.top, DesignSystem.Spacing.small)

                // Document type picker + Analyze button
                HStack(spacing: DesignSystem.Spacing.small) {
                    Picker("Type:", selection: Binding(
                        get: { viewModel.textInputType },
                        set: { viewModel.textInputType = $0 }
                    )) {
                        ForEach(TextInputType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)

                    if viewModel.textInputType == .other {
                        TextField("Describe your content...", text: Binding(
                            get: { viewModel.textInputTypeDescription },
                            set: { viewModel.textInputTypeDescription = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    }

                    Spacer()

                    // Action buttons — wrap vertically if horizontal space is tight
                    actionButtons
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.xs)

                // Document tabs
                if hasMultipleDocuments {
                    documentTabs
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                }
            )
            .frame(minHeight: maxHeaderHeight)

            Divider().opacity(0.15)

            // Document tabs (shared between panels 1 & 2)
            if false { // tabs moved into header area above
                documentTabs
                Divider().opacity(0.15)
            }

            // Text input area
            ZStack(alignment: .topLeading) {
                if let savedDoc = selectedSourceDocument {
                    // Viewing a saved document's original text
                    ScrollView {
                        Text(savedDoc.originalText)
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DesignSystem.Spacing.medium)
                    }
                } else if let cachedOriginal = viewModel.cachedOriginalAttributed, viewModel.result != nil {
                    // Current document after analysis: highlighted original text
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
                } else {
                    // Before analysis: editable text input
                    // Placeholder — only visible when no text
                    if viewModel.inputText.isEmpty {
                        Text("Paste or drop a document here (.docx, .pdf, .rtf, .txt)")
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                            .padding(.horizontal, DesignSystem.Spacing.medium)
                            .padding(.top, DesignSystem.Spacing.medium)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: Binding(
                        get: { viewModel.inputText },
                        set: { viewModel.inputText = $0 }
                    ))
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(DesignSystem.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                                .fill(Color.white.opacity(0.3))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                        .padding(DesignSystem.Spacing.small)
                }

                // Invisible drop receiver on top — NSScrollView eats drops,
                // so we need a transparent layer above it to catch file drops.
                // Only active when not yet analyzed (so it doesn't block FastTextView interaction).
                if viewModel.result == nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .allowsHitTesting(isDropTargeted) // Only intercept hits during active drag
                        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                            handleFileDrop(providers)
                        }
                }

                // Drop highlight overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(DesignSystem.Colors.primaryTeal, lineWidth: 2)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.05))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "doc.badge.arrow.up")
                                    .font(.system(size: 32))
                                Text("Drop document here")
                                    .font(DesignSystem.Typography.subheading)
                            }
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                        )
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - File Drop

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            let text = Self.extractText(from: url)
            guard let text, !text.isEmpty else { return }

            DispatchQueue.main.async { [weak viewModel] in
                guard let viewModel else { return }
                if viewModel.inputText.isEmpty {
                    viewModel.inputText = text
                } else {
                    viewModel.inputText += "\n\n" + text
                }
            }
        }
        return true
    }

    /// Extract plain text from .docx, .pdf, .rtf, .txt, and other text files
    private static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        // Plain text files
        if ["txt", "csv", "md", "text"].contains(ext) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        // PDF — use PDFKit for reliable text extraction
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return nil }
            var text = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let pageText = page.string {
                    if !text.isEmpty { text += "\n\n" }
                    text += pageText
                }
            }
            return text.isEmpty ? nil : text
        }

        // Word (.docx), RTF, and other rich formats — NSAttributedString handles natively
        let options: [NSAttributedString.DocumentReadingOptionKey: Any]
        switch ext {
        case "doc":
            options = [.documentType: NSAttributedString.DocumentType.docFormat]
        case "rtf", "rtfd":
            options = [.documentType: NSAttributedString.DocumentType.rtf]
        default:
            // .docx and other formats — let NSAttributedString auto-detect
            options = [:]
        }

        // NSAttributedString can read .docx natively on macOS
        if let attrString = try? NSAttributedString(
            url: url,
            options: options,
            documentAttributes: nil
        ) {
            return attrString.string
        }

        // Fallback: try reading as plain text
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Document Tabs

    private var hasMultipleDocuments: Bool {
        !viewModel.sourceDocuments.isEmpty
    }

    /// Selected saved document (nil if viewing current)
    private var selectedSourceDocument: SourceDocument? {
        guard let id = selectedDocId else { return nil }
        return viewModel.sourceDocuments.first { $0.id == id }
    }

    private var documentTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.sourceDocuments) { doc in
                    let isSelected = selectedDocId == doc.id
                    Button(action: { selectedDocId = doc.id }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 10))
                            Text(doc.name)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.3) : DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .cornerRadius(6)
                        .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                // Current document tab
                if viewModel.result != nil {
                    let isSelected = selectedDocId == nil
                    let docNum = viewModel.sourceDocuments.count + 1
                    let currentLabel = "Document \(docNum) (\(viewModel.textInputTypeLabel))"
                    Button(action: { selectedDocId = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text(currentLabel)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.3) : DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .cornerRadius(6)
                        .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.xs)
        }
        .frame(height: 32)
    }

    // MARK: - Panel 2: Redacted Text

    private var redactedPanel: some View {
        VStack(spacing: 0) {
            // Header — synced height with other panels
            VStack(spacing: 0) {
                HStack {
                    Text("Redacted Text")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    if viewModel.hasAnyContent {
                        let copyLabel = hasMultipleDocuments
                            ? (viewModel.justCopiedRedacted ? "Copied!" : "Copy All")
                            : (viewModel.justCopiedRedacted ? "Copied!" : "Copy")
                        Button(action: {
                            if viewModel.hasPendingChanges {
                                showPendingChangesAlert = true
                            } else {
                                viewModel.copyRedactedText()
                            }
                        }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: viewModel.justCopiedRedacted ? "checkmark" : "doc.on.doc")
                                    .frame(width: 14, height: 14)
                                Text(copyLabel)
                                    .frame(minWidth: 50)
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedRedacted)
                        .alert("Unapplied Changes", isPresented: $showPendingChangesAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Apply & Copy") {
                                viewModel.applyChanges()
                                viewModel.copyRedactedText()
                            }
                        } message: {
                            Text("You have entity changes that haven't been applied to the redacted text. Apply them first so the copied text reflects your changes?")
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.top, DesignSystem.Spacing.small)

                // Document tabs in redacted panel too
                if hasMultipleDocuments {
                    documentTabs
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                }
            )
            .frame(minHeight: maxHeaderHeight)

            Divider().opacity(0.15)

            // Content
            if viewModel.combinedRedactedText.isEmpty {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
                    Text("Redacted text will appear here")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let savedDoc = selectedSourceDocument {
                // Viewing a saved document's redacted text
                ScrollView {
                    Text(savedDoc.redactedText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let cachedRedacted = viewModel.cachedRedactedAttributed {
                // Current document with highlights
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(viewModel.combinedRedactedText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Panel 3: Paste Back / Restored

    private var restorePanel: some View {
        VStack(spacing: 0) {
            // Header — synced height with other panels
            VStack(spacing: 0) {
                HStack {
                    Text(viewModel.restoredText.isEmpty ? "Paste Processed Text" : "Restored Text")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    if !viewModel.restoredText.isEmpty {
                        // Copy restored text
                        Button(action: { viewModel.copyRestoredText() }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: viewModel.justCopiedRestored ? "checkmark" : "doc.on.doc")
                                    .frame(width: 14, height: 14)
                                Text(viewModel.justCopiedRestored ? "Copied!" : "Copy")
                                    .frame(minWidth: 50)
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedRestored)

                        // Edit button to go back to paste-back
                        Button(action: { viewModel.clearRestore() }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else if !viewModel.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Restore Names button
                        Button(action: { viewModel.restoreNames() }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "lock.open.fill")
                                    .frame(width: 14, height: 14)
                                Text("Restore Names")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!viewModel.hasAnyContent)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.top, DesignSystem.Spacing.small)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HeaderHeightKey.self, value: geo.size.height)
                }
            )
            .frame(minHeight: maxHeaderHeight)

            Divider().opacity(0.15)

            // Content: paste area OR restored text
            if viewModel.restoredText.isEmpty {
                // Paste-back text editor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.pastedText)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(DesignSystem.Spacing.small)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                                .fill(Color.white.opacity(0.3))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
                        .padding(DesignSystem.Spacing.small)

                    if viewModel.pastedText.isEmpty {
                        VStack(spacing: DesignSystem.Spacing.small) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 32))
                                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.4))
                            Text("Paste AI-processed text here")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                            Text("Then click Restore Names")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Show restored text with markdown formatting
                ScrollView {
                    Text(MarkdownParser.parseToAttributedString(
                        viewModel.restoredText,
                        baseFont: .systemFont(ofSize: 14)
                    ))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Entity Sidebar

    @State private var isSidebarCollapsed: Bool = false

    private var entitySidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if !isSidebarCollapsed {
                    Text("Entities (\(viewModel.allEntities.count))")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Spacer()

                    // Deep Scan button
                    Button(action: { Task { await viewModel.runDeepScan() } }) {
                        if viewModel.isRunningDeepScan {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .disabled(viewModel.result == nil || viewModel.isRunningDeepScan)
                    .help("Deep Scan — find additional entities")

                    Button(action: { viewModel.openAddCustomEntity() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .help("Add custom entity")

                    // Duplicate finder button
                    Button(action: { viewModel.openDuplicateFinder() }) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .help("Find duplicate names")
                    .disabled(personEntityCount < 2)
                    .opacity(personEntityCount < 2 ? 0.4 : 1.0)
                }

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isSidebarCollapsed.toggle() } }) {
                    Image(systemName: isSidebarCollapsed ? "chevron.right" : "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .accessibilityLabel(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
            }
            .frame(height: 40)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            if !isSidebarCollapsed {
                Divider().opacity(0.15)

                // Success message
                if let message = viewModel.successMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.success)
                            .font(.system(size: 11))
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surface)
                }

                // Deep scan result message
                if viewModel.showDeepScanCompleteMessage {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.deepScanFindingsCount > 0 ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(viewModel.deepScanFindingsCount > 0 ? .orange : .green)
                            .font(.system(size: 11))
                        Text(viewModel.deepScanFindingsCount > 0
                             ? "Found \(viewModel.deepScanFindingsCount) additional"
                             : "No additional entities found")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Button(action: { viewModel.showDeepScanCompleteMessage = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.surface)
                }

                // Entity list grouped by type
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.small) {
                        // Deep Scan findings section
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
        .frame(width: isSidebarCollapsed ? 40 : 270)
        .glassPanel(cornerRadius: DesignSystem.CornerRadius.xlarge)
        .animation(.easeInOut(duration: 0.2), value: isSidebarCollapsed)
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

    private var personEntityCount: Int {
        viewModel.allEntities.filter { $0.type.isPerson && !viewModel.isEntityExcluded($0) }.count
    }

    /// Entity types in display order
    private var groupedEntityTypes: [EntityType] {
        [.personClient, .personProvider, .personOther, .date, .location, .organization, .contact, .identifier, .numericAll]
    }

    /// Get entities for a specific type (excluding deep scan findings shown in separate section)
    private func entitiesForType(_ type: EntityType) -> [Entity] {
        let deepIds = Set(viewModel.deepScanFindings.map { $0.id })
        return viewModel.allEntities.filter {
            $0.type == type && !deepIds.contains($0.id)
        }
    }
}

// MARK: - Header Height Sync

/// Preference key to sync header heights across panels
private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

