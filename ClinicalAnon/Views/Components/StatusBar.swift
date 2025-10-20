//
//  StatusBar.swift
//  ClinicalAnon
//
//  Purpose: Status bar showing processing progress
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Status Bar

/// Status bar showing processing status and progress
struct StatusBar: View {

    // MARK: - Properties

    let isProcessing: Bool
    let progress: Double
    let statusMessage: String

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            if isProcessing {
                // Progress indicator
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                // Progress percentage
                Text("\(Int(progress * 100))%")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 40, alignment: .trailing)

                // Status message
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()
            } else {
                EmptyView()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Result Summary Bar

/// Status bar showing anonymization result summary
struct ResultSummaryBar: View {
    let result: AnonymizationResult?

    var body: some View {
        if let result = result {
            HStack(spacing: DesignSystem.Spacing.medium) {
                // Entity count
                StatusBadge(
                    icon: "checkmark.circle.fill",
                    label: "\(result.entityCount) \(result.entityCount == 1 ? "entity" : "entities")",
                    color: DesignSystem.Colors.success
                )

                // Replacement count
                StatusBadge(
                    icon: "arrow.triangle.2.circlepath",
                    label: "\(result.replacementCount) \(result.replacementCount == 1 ? "replacement" : "replacements")",
                    color: DesignSystem.Colors.primaryTeal
                )

                Spacer()

                // Processing time
                if let metadata = result.metadata,
                   let processingTime = metadata.processingTime {
                    Text(String(format: "%.2fs", processingTime))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.background)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14))

            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Error Banner

/// Banner displaying error messages
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DesignSystem.Colors.error)

            Text(message)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.error.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.error, lineWidth: 1)
        )
    }
}

// MARK: - Success Banner

/// Banner displaying success messages
struct SuccessBanner: View {
    let message: String
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.Colors.success)

            Text(message)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.success.opacity(0.1))
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.success, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct StatusBar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Processing
            StatusBar(
                isProcessing: true,
                progress: 0.65,
                statusMessage: "Processing response..."
            )
            .frame(width: 600)
            .previewDisplayName("Processing")

            // Result summary
            ResultSummaryBar(result: AnonymizationResult.sample)
            .frame(width: 600)
            .previewDisplayName("Result Summary")

            // Error banner
            ErrorBanner(
                message: "Could not connect to Ollama. Please ensure it is running.",
                onDismiss: {}
            )
            .frame(width: 600)
            .padding()
            .previewDisplayName("Error")

            // Success banner
            SuccessBanner(
                message: "Text copied to clipboard successfully!",
                onDismiss: {}
            )
            .frame(width: 600)
            .padding()
            .previewDisplayName("Success")
        }
    }
}
#endif
