//
//  LiveHighlightedSegment.swift
//  ClinicalAnon
//
//  Purpose: Entity-highlighted text display for live transcript segments
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Live Highlighted Segment

/// Displays transcript text with detected entities highlighted
struct LiveHighlightedSegment: View {

    // MARK: - Properties

    let text: String
    let entities: [Entity]

    // MARK: - Body

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
    }

    // MARK: - Private Methods

    /// Build attributed string with entity highlighting
    private var attributedText: AttributedString {
        var attributed = AttributedString(text)

        // Highlight each entity found in this text
        for entity in entities {
            highlightEntity(entity, in: &attributed)
        }

        return attributed
    }

    /// Highlight all occurrences of an entity in the attributed string
    private func highlightEntity(_ entity: Entity, in attributed: inout AttributedString) {
        let searchText = entity.originalText

        // Search directly in the AttributedString (avoids String/AttributedString index conversion issues)
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(of: searchText, options: .caseInsensitive) {
            attributed[range].backgroundColor = entity.type.highlightColor.opacity(0.3)
            searchStart = range.upperBound
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LiveHighlightedSegment_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            // No entities
            LiveHighlightedSegment(
                text: "The patient reported feeling better after the session.",
                entities: []
            )
            .padding()

            // With entities
            LiveHighlightedSegment(
                text: "Jane Smith discussed her symptoms with Dr. Wilson in Auckland.",
                entities: [
                    Entity(
                        originalText: "Jane Smith",
                        replacementCode: "[CLIENT_A]",
                        type: .personClient,
                        positions: [[0, 10]],
                        confidence: 0.95
                    ),
                    Entity(
                        originalText: "Dr. Wilson",
                        replacementCode: "[PROVIDER_A]",
                        type: .personProvider,
                        positions: [[40, 50]],
                        confidence: 0.98
                    ),
                    Entity(
                        originalText: "Auckland",
                        replacementCode: "[LOCATION_A]",
                        type: .location,
                        positions: [[54, 62]],
                        confidence: 0.85
                    )
                ]
            )
            .padding()

            // Multiple occurrences of same entity
            LiveHighlightedSegment(
                text: "Jane said she felt better. Jane will return next week.",
                entities: [
                    Entity(
                        originalText: "Jane",
                        replacementCode: "[CLIENT_A]",
                        type: .personClient,
                        positions: [[0, 4], [27, 31]],
                        confidence: 0.95
                    )
                ]
            )
            .padding()
        }
        .frame(width: 500)
        .padding()
    }
}
#endif
