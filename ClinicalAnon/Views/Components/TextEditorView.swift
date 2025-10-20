//
//  TextEditorView.swift
//  ClinicalAnon
//
//  Purpose: Reusable text editor component with metrics
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Text Editor View

/// Reusable text editor with label, metrics, and optional actions
struct TextEditorView: View {

    // MARK: - Properties

    let title: String
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool
    let showMetrics: Bool
    let maxHeight: CGFloat?

    // MARK: - Initialization

    init(
        title: String,
        text: Binding<String>,
        placeholder: String = "Enter text...",
        isEditable: Bool = true,
        showMetrics: Bool = true,
        maxHeight: CGFloat? = nil
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.showMetrics = showMetrics
        self.maxHeight = maxHeight
    }

    // MARK: - Computed Properties

    private var characterCount: Int {
        text.count
    }

    private var wordCount: Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { !$0.isEmpty }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Header
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                if showMetrics && !text.isEmpty {
                    MetricsView(characterCount: characterCount, wordCount: wordCount)
                }
            }

            // Text editor
            if isEditable {
                EditableTextView(text: $text, placeholder: placeholder, maxHeight: maxHeight)
            } else {
                ReadOnlyTextView(text: text, placeholder: placeholder, maxHeight: maxHeight)
            }
        }
    }
}

// MARK: - Editable Text View

private struct EditableTextView: View {
    @Binding var text: String
    let placeholder: String
    let maxHeight: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if text.isEmpty {
                Text(placeholder)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                    .padding(DesignSystem.Spacing.small)
            }

            // Text editor
            TextEditor(text: $text)
                .font(DesignSystem.Typography.monospace)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(DesignSystem.Spacing.xs)
        }
        .frame(maxHeight: maxHeight)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Read-Only Text View

private struct ReadOnlyTextView: View {
    let text: String
    let placeholder: String
    let maxHeight: CGFloat?

    var body: some View {
        ScrollView {
            if text.isEmpty {
                Text(placeholder)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.small)
            } else {
                Text(text)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignSystem.Spacing.small)
            }
        }
        .frame(maxHeight: maxHeight)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Metrics View

private struct MetricsView: View {
    let characterCount: Int
    let wordCount: Int

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            MetricBadge(label: "\(wordCount)", subtext: "words")
            MetricBadge(label: "\(characterCount)", subtext: "chars")
        }
    }
}

private struct MetricBadge: View {
    let label: String
    let subtext: String

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text(subtext)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, 2)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Text Editor with Actions

/// Text editor with action buttons (copy, clear, etc.)
struct TextEditorWithActionsView: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool
    let onCopy: (() -> Void)?
    let onClear: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Header with actions
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                // Action buttons
                HStack(spacing: DesignSystem.Spacing.xs) {
                    if !text.isEmpty {
                        if let onCopy = onCopy {
                            Button(action: onCopy) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        if let onClear = onClear, isEditable {
                            Button(action: onClear) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                    Text("Clear")
                                }
                                .font(DesignSystem.Typography.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    // Metrics
                    MetricsView(
                        characterCount: text.count,
                        wordCount: text.components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }.count
                    )
                }
            }

            // Text editor
            TextEditorView(
                title: "",
                text: $text,
                placeholder: placeholder,
                isEditable: isEditable,
                showMetrics: false
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TextEditorView_Previews: PreviewProvider {
    @State static var editableText = "Jane Smith attended her session on March 15, 2024. She reported improvement in managing anxiety symptoms."
    @State static var emptyText = ""

    static var previews: some View {
        Group {
            // Editable with text
            TextEditorView(
                title: "Original Text",
                text: $editableText,
                placeholder: "Enter clinical text..."
            )
            .frame(width: 500, height: 200)
            .padding()
            .previewDisplayName("Editable with Text")

            // Empty editable
            TextEditorView(
                title: "Original Text",
                text: $emptyText,
                placeholder: "Enter clinical text..."
            )
            .frame(width: 500, height: 200)
            .padding()
            .previewDisplayName("Empty")

            // Read-only
            TextEditorView(
                title: "Anonymized Text",
                text: .constant("[CLIENT_A] attended her session on [DATE_A]. She reported improvement in managing anxiety symptoms."),
                placeholder: "Anonymized text will appear here...",
                isEditable: false
            )
            .frame(width: 500, height: 200)
            .padding()
            .previewDisplayName("Read-Only")

            // With actions
            TextEditorWithActionsView(
                title: "Anonymized Text",
                text: $editableText,
                placeholder: "Anonymized text will appear here...",
                isEditable: false,
                onCopy: { print("Copy") },
                onClear: nil
            )
            .frame(width: 500, height: 200)
            .padding()
            .previewDisplayName("With Actions")
        }
    }
}
#endif
