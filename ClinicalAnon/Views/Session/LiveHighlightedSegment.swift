//
//  LiveHighlightedSegment.swift
//  ClinicalAnon
//
//  Purpose: Entity-highlighted text display for live transcript segments
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Live Highlighted Segment

/// Displays transcript text with detected entities highlighted
/// Uses the same NSRange-based approach as HighlightedTextView for consistency
struct LiveHighlightedSegment: View {

    // MARK: - Properties

    let text: String
    let entities: [Entity]

    // MARK: - Body

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
    }

    // MARK: - Attributed Text

    /// Build attributed string with entity highlighting using NSRange (same as HighlightedTextView)
    private var attributedText: AttributedString {
        var attributed = AttributedString(text)

        // Apply default styling
        attributed.foregroundColor = Color(nsColor: .labelColor)

        // Use NSString for consistent position handling
        let nsText = text as NSString

        // Find and highlight each entity by string matching
        for entity in entities {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.location < nsText.length {
                let foundRange = nsText.range(of: entity.originalText, options: .caseInsensitive, range: searchRange)

                guard foundRange.location != NSNotFound else { break }

                // Convert NSRange to AttributedString range
                if let range = Range<AttributedString.Index>(foundRange, in: attributed) {
                    attributed[range].backgroundColor = entity.type.highlightColor.opacity(0.3)
                }

                // Move search past this match
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsText.length - searchRange.location
            }
        }

        return attributed
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
