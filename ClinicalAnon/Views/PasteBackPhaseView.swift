//
//  PasteBackPhaseView.swift
//  Redactor
//
//  Purpose: Simplified Phase 2 when AI analysis is disabled.
//           User copies redacted text out, processes with external AI,
//           then pastes the result back for restore.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Paste Back Phase View

/// Phase 2 (AI disabled): Two-pane view — redacted text on left, paste-back area on right
struct PasteBackPhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel
    @State private var pastedText: String = ""
    @State private var justCopied: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Content: Redacted text (left) | Paste back (right)
            HStack(spacing: 0) {
                redactedTextPane
                Divider().opacity(0.3)
                pasteBackPane
            }

            Divider().opacity(0.3)

            // Footer with navigation
            footerBar
        }
    }

    // MARK: - Redacted Text Pane

    private var redactedTextPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(documentCountLabel)
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Button(action: copyRedactedText) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .frame(width: 14, height: 14)
                        Text(justCopied ? "Copied!" : "Copy to Clipboard")
                            .frame(minWidth: 100)
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(redactedText.isEmpty)
                .animation(.easeInOut(duration: 0.2), value: justCopied)
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if redactedText.isEmpty {
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                    Text("No redacted text available")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    TextContentCard(isSourcePanel: true, isProcessed: true) {
                        Text(redactedText)
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Paste Back Pane

    private var pasteBackPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Paste Processed Text")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                if !pastedText.isEmpty {
                    Button(action: { pastedText = "" }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "xmark")
                            Text("Clear")
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Text editor for pasting
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(DesignSystem.Spacing.medium)

                if pastedText.isEmpty {
                    VStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 32))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.4))
                        Text("Paste your externally processed text here")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                        Text("Use ⌘V to paste")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .background(DesignSystem.Colors.surface)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button("← Back") {
                viewModel.goToPreviousPhase()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            // Continue button
            Button(action: continueToRestore) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(DesignSystem.Typography.body)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Helpers

    private var documentCountLabel: String {
        let count = viewModel.improveState.sourceDocuments.count
        return count > 1 ? "Redacted Text (\(count) documents)" : "Redacted Text"
    }

    /// Combined redacted text from all source documents (or just the current one if single doc)
    private var redactedText: String {
        let docs = viewModel.improveState.sourceDocuments
        if docs.count > 1 {
            // Multiple documents — show all with headers, matching AI flow format
            return docs.map { doc in
                """
                === \(doc.name)\(doc.description.isEmpty ? "" : " (\(doc.description))") ===

                \(doc.redactedText)
                """
            }.joined(separator: "\n\n")
        }
        return viewModel.displayedRedactedText
    }

    private func copyRedactedText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(redactedText, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            justCopied = false
        }
        // Auto-clear clipboard after 5 minutes for security (matches RedactPhaseState behavior)
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            NSPasteboard.general.clearContents()
        }
    }

    private func continueToRestore() {
        let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Set the pasted text as the "AI output" so the existing restore flow works
        viewModel.improveState.aiOutput = trimmed
        viewModel.improveState.currentDocument = trimmed
        viewModel.continueToNextPhase()
    }
}
