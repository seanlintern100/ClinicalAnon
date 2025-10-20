//
//  ActionBar.swift
//  ClinicalAnon
//
//  Purpose: Action bar with primary buttons
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Action Bar

/// Action bar with primary action buttons
struct ActionBar: View {

    // MARK: - Properties

    let onAnalyze: () -> Void
    let onClearAll: () -> Void
    let isAnalyzing: Bool
    let hasText: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Clear All button
            Button(action: onClearAll) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "trash")
                    Text("Clear All")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!hasText || isAnalyzing)

            Spacer()

            // Analyze button
            Button(action: onAnalyze) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    if isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isAnalyzing ? "Analyzing..." : "Analyze")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!hasText || isAnalyzing)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Copy Action Bar

/// Action bar with copy and export actions
struct CopyActionBar: View {
    let onCopy: () -> Void
    let onExport: (() -> Void)?
    let hasContent: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            // Export button (optional)
            if let onExport = onExport {
                Button(action: onExport) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasContent)
            }

            // Copy button
            Button(action: onCopy) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy to Clipboard")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!hasContent)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Preview

#if DEBUG
struct ActionBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Ready state
            ActionBar(
                onAnalyze: {},
                onClearAll: {},
                isAnalyzing: false,
                hasText: true
            )
            .frame(width: 600)
            .previewDisplayName("Ready")

            // Analyzing state
            ActionBar(
                onAnalyze: {},
                onClearAll: {},
                isAnalyzing: true,
                hasText: true
            )
            .frame(width: 600)
            .previewDisplayName("Analyzing")

            // No text
            ActionBar(
                onAnalyze: {},
                onClearAll: {},
                isAnalyzing: false,
                hasText: false
            )
            .frame(width: 600)
            .previewDisplayName("No Text")

            // Copy bar
            CopyActionBar(
                onCopy: {},
                onExport: {},
                hasContent: true
            )
            .frame(width: 600)
            .previewDisplayName("Copy Bar")
        }
    }
}
#endif
