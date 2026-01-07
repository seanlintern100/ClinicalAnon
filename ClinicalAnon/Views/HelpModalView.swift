//
//  HelpModalView.swift
//  ClinicalAnon
//
//  Purpose: Modal view for displaying help content with styled markdown
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Help Guide Modal View

/// Modal sheet for displaying help documentation
struct HelpGuideModalView: View {

    let contentType: HelpContentType
    @Environment(\.dismiss) private var dismiss

    /// Callback to show the full guide (used by phase-specific modals)
    var onShowFullGuide: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().opacity(0.15)

            // Scrollable content
            ScrollView {
                MarkdownRenderer(markdown: contentType.content)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.small)
            }

            Divider().opacity(0.15)

            // Footer
            footer
        }
        .frame(width: 550, height: 500)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contentType.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(contentType.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close help")
        }
        .padding(DesignSystem.Spacing.small)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Show "View Full Guide" button only for phase-specific help
            if contentType != .fullGuide, let showFullGuide = onShowFullGuide {
                Button(action: {
                    dismiss()
                    // Slight delay to allow dismiss animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showFullGuide()
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "book")
                            .font(.system(size: 11))
                        Text("View Full Guide")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.primaryTeal)
            .font(.system(size: 12))
        }
        .padding(DesignSystem.Spacing.small)
    }
}

// MARK: - Preview

#if DEBUG
struct HelpGuideModalView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HelpGuideModalView(contentType: .redactPhase)
                .previewDisplayName("Redact Phase Help")

            HelpGuideModalView(contentType: .fullGuide)
                .previewDisplayName("Full Guide")
        }
    }
}
#endif
