//
//  QuotesListView.swift
//  ClinicalAnon
//
//  Purpose: List of significant quotes from the session
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Quotes List View

/// List of Quote items with curly quotes and significance
struct QuotesListView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService

    // MARK: - Body

    var body: some View {
        Group {
            if assistantService.state.quotes.isEmpty {
                emptyState
            } else {
                quotesList
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "quote.bubble")
                .font(.largeTitle)
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No quotes yet")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Significant phrases, metaphors, and emotionally charged statements will be captured here")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Quotes List

    private var quotesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                ForEach(assistantService.state.quotes) { quote in
                    quoteRow(quote)
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Quote Row

    private func quoteRow(_ quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            // Quote text with curly quotes
            Text("\u{201C}\(quote.text)\u{201D}")
                .font(DesignSystem.Typography.body)
                .italic()
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            // Significance
            if !quote.significance.isEmpty {
                Text(quote.significance)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // Metadata
            HStack(spacing: DesignSystem.Spacing.small) {
                if quote.timestamp > 0 {
                    Text(formatTime(quote.timestamp))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                if quote.isManuallyAdded {
                    Text("Manual")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button(role: .destructive) {
                assistantService.deleteQuote(quote)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#if DEBUG
struct QuotesListView_Previews: PreviewProvider {
    static var previews: some View {
        QuotesListView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 320, height: 400)
    }
}
#endif
