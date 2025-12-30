//
//  HighlightedTextView.swift
//  ClinicalAnon
//
//  Purpose: Displays text with highlighted entities
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Highlighted Text View

/// Displays text with entities highlighted in different colors
struct HighlightedTextView: View {

    // MARK: - Properties

    let text: String
    let entities: [Entity]
    let onEntityClick: ((Entity) -> Void)?

    // MARK: - Body

    var body: some View {
        ScrollView {
            Text(attributedText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.small)
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Attributed Text

    private var attributedText: AttributedString {
        var attributedString = AttributedString(text)

        // Apply default font
        attributedString.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        // Highlight each entity
        for entity in entities {
            for position in entity.positions {
                guard position.count >= 2 else { continue }

                let start = position[0]
                let end = position[1]

                // Validate bounds
                guard start >= 0, end <= text.count, start < end else { continue }

                // Get string indices
                let startIndex = text.index(text.startIndex, offsetBy: start)
                let endIndex = text.index(text.startIndex, offsetBy: end)

                // Convert to AttributedString range
                if let range = Range<AttributedString.Index>(
                    NSRange(location: start, length: end - start),
                    in: attributedString
                ) {
                    // Apply highlighting based on entity type
                    attributedString[range].backgroundColor = colorForEntityType(entity.type).opacity(0.3)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                }
            }
        }

        return attributedString
    }

    // MARK: - Helper Methods

    private func colorForEntityType(_ type: EntityType) -> Color {
        switch type {
        case .personClient:
            return DesignSystem.Colors.primaryTeal
        case .personProvider:
            return DesignSystem.Colors.sage
        case .personOther:
            return DesignSystem.Colors.orange
        case .date:
            return Color.purple
        case .location:
            return Color.blue
        case .organization:
            return Color.green
        case .identifier:
            return Color.red
        case .contact:
            return Color.pink
        case .numericAll:
            return Color.orange
        }
    }
}

// MARK: - Highlighted Text with Legend

/// Highlighted text view with a color legend
struct HighlightedTextWithLegendView: View {
    let text: String
    let entities: [Entity]
    let onEntityClick: ((Entity) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            // Legend
            EntityLegendView(entities: entities)

            // Highlighted text
            HighlightedTextView(
                text: text,
                entities: entities,
                onEntityClick: onEntityClick
            )
        }
    }
}

// MARK: - Entity Legend

struct EntityLegendView: View {
    let entities: [Entity]

    private var entityTypes: [EntityType] {
        let types = Set(entities.map { $0.type })
        return Array(types).sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        if !entityTypes.isEmpty {
            HStack(spacing: DesignSystem.Spacing.small) {
                Text("Legend:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                ForEach(entityTypes) { type in
                    LegendItem(type: type)
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.xs)
            .background(DesignSystem.Colors.background)
            .cornerRadius(DesignSystem.CornerRadius.small)
        }
    }
}

struct LegendItem: View {
    let type: EntityType

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForEntityType(type).opacity(0.6))
                .frame(width: 8, height: 8)

            Text(type.displayName)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, 2)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }

    private func colorForEntityType(_ type: EntityType) -> Color {
        switch type {
        case .personClient:
            return DesignSystem.Colors.primaryTeal
        case .personProvider:
            return DesignSystem.Colors.sage
        case .personOther:
            return DesignSystem.Colors.orange
        case .date:
            return Color.purple
        case .location:
            return Color.blue
        case .organization:
            return Color.green
        case .identifier:
            return Color.red
        case .contact:
            return Color.pink
        case .numericAll:
            return Color.orange
        }
    }
}

// MARK: - Preview

#if DEBUG
struct HighlightedTextView_Previews: PreviewProvider {
    static let sampleText = """
    Jane Smith attended her session on March 15, 2024.
    Dr. Wilson conducted the assessment at Auckland Clinic.
    Jane reported improvement in managing anxiety symptoms.
    Contact: jane@email.com, Phone: 021-555-0123.
    """

    static let sampleEntities: [Entity] = [
        Entity(
            originalText: "Jane Smith",
            replacementCode: "[CLIENT_A]",
            type: .personClient,
            positions: [[0, 10], [92, 102]]
        ),
        Entity(
            originalText: "March 15, 2024",
            replacementCode: "[DATE_A]",
            type: .date,
            positions: [[39, 53]]
        ),
        Entity(
            originalText: "Dr. Wilson",
            replacementCode: "[PROVIDER_A]",
            type: .personProvider,
            positions: [[55, 65]]
        ),
        Entity(
            originalText: "Auckland Clinic",
            replacementCode: "[LOCATION_A]",
            type: .location,
            positions: [[96, 111]]
        ),
        Entity(
            originalText: "jane@email.com",
            replacementCode: "[CONTACT_A]",
            type: .contact,
            positions: [[161, 175]]
        ),
        Entity(
            originalText: "021-555-0123",
            replacementCode: "[CONTACT_B]",
            type: .contact,
            positions: [[184, 196]]
        )
    ]

    static var previews: some View {
        Group {
            // With highlighting
            HighlightedTextView(
                text: sampleText,
                entities: sampleEntities,
                onEntityClick: nil
            )
            .frame(width: 500, height: 200)
            .padding()
            .previewDisplayName("With Highlighting")

            // With legend
            HighlightedTextWithLegendView(
                text: sampleText,
                entities: sampleEntities,
                onEntityClick: nil
            )
            .frame(width: 500, height: 250)
            .padding()
            .previewDisplayName("With Legend")

            // No entities
            HighlightedTextView(
                text: "No entities in this text.",
                entities: [],
                onEntityClick: nil
            )
            .frame(width: 500, height: 100)
            .padding()
            .previewDisplayName("No Entities")
        }
    }
}
#endif
