//
//  LiveFeedItemView.swift
//  ClinicalAnon
//
//  Purpose: Individual feed item row with hover actions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Live Feed Item View

/// Individual feed item with icon and content
struct LiveFeedItemView: View {

    // MARK: - Properties

    let item: FeedItem

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            // Icon
            icon

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Type label and timestamp
                header

                // Main content
                Text(item.content)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                // Rationale
                if !item.rationale.isEmpty {
                    Text(item.rationale)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DesignSystem.Spacing.small)
        .background(itemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    // MARK: - Icon

    private var icon: some View {
        Image(systemName: item.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(item.iconColor)
            .frame(width: 24, height: 24)
            .background(item.iconColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            // Type label
            Text(typeLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(item.iconColor)
                .textCase(.uppercase)

            // Timestamp
            Text(item.formattedTimestamp)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Computed Properties

    private var typeLabel: String {
        switch item.itemType {
        case .flag:
            return item.flagSeverity?.displayName ?? "FLAG"
        case .suggestion:
            return "SUGGESTION"
        case .detail:
            return "DETAIL"
        case .agendaUpdate:
            return "AGENDA"
        }
    }

    private var itemBackground: Color {
        if item.flagSeverity == .safety {
            return Color.red.opacity(0.08)
        }
        return DesignSystem.Colors.surface
    }

    private var borderColor: Color {
        if item.flagSeverity == .safety {
            return Color.red.opacity(0.3)
        }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        item.flagSeverity == .safety ? 1.5 : 0
    }
}

// MARK: - Preview

#if DEBUG
struct LiveFeedItemView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            // Safety flag
            LiveFeedItemView(
                item: FeedItem(
                    itemType: .flag,
                    content: "Client mentioned \"ending it\"",
                    rationale: "Risk language detected - requires attention",
                    timestamp: 165,
                    flagSeverity: .safety
                )
            )

            // Important flag
            LiveFeedItemView(
                item: FeedItem(
                    itemType: .flag,
                    content: "Significant revelation about relationship",
                    rationale: "First mention of relationship breakdown",
                    timestamp: 270,
                    flagSeverity: .important
                )
            )

            // Suggestion
            LiveFeedItemView(
                item: FeedItem(
                    itemType: .suggestion,
                    content: "Consider exploring family dynamics",
                    rationale: "Theme mentioned 3 times without exploration",
                    timestamp: 192
                )
            )

            // Detail
            LiveFeedItemView(
                item: FeedItem(
                    itemType: .detail,
                    content: "Client has two siblings",
                    rationale: "",
                    timestamp: 240,
                    detailCategory: "Relationship"
                )
            )
        }
        .padding()
        .frame(width: 300)
        .background(DesignSystem.Colors.background)
    }
}
#endif
