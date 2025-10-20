//
//  Entity.swift
//  ClinicalAnon
//
//  Purpose: Model representing a detected entity (PII) in clinical text
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Model

/// Represents a single piece of personally identifiable information (PII) detected in text
struct Entity: Identifiable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier for this entity
    let id: UUID

    /// The original text that was detected (e.g., "Jane Smith")
    let originalText: String

    /// The replacement code (e.g., "[CLIENT_A]")
    let replacementCode: String

    /// The type of entity
    let type: EntityType

    /// Positions where this entity appears in the original text
    /// Array of [startIndex, endIndex] pairs
    let positions: [[Int]]

    /// Confidence score from the LLM (0.0 to 1.0)
    /// Optional because not all detection methods provide confidence
    let confidence: Double?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        originalText: String,
        replacementCode: String,
        type: EntityType,
        positions: [[Int]],
        confidence: Double? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.replacementCode = replacementCode
        self.type = type
        self.positions = positions
        self.confidence = confidence
    }

    // MARK: - Computed Properties

    /// Total number of occurrences in the text
    var occurrenceCount: Int {
        return positions.count
    }

    /// First occurrence position (for sorting/display)
    var firstPosition: Int? {
        return positions.first?.first
    }

    /// Display text for UI lists
    var displayText: String {
        return "\(originalText) → \(replacementCode)"
    }

    /// Short form for compact display
    var shortDisplay: String {
        let typeIcon = type.iconName
        return "\(typeIcon) \(originalText)"
    }

    // MARK: - Helper Methods

    /// Check if this entity contains a specific position
    func contains(position: Int) -> Bool {
        return positions.contains { range in
            guard range.count >= 2 else { return false }
            return position >= range[0] && position < range[1]
        }
    }

    /// Check if this entity overlaps with another entity
    func overlaps(with other: Entity) -> Bool {
        for thisRange in positions {
            guard thisRange.count >= 2 else { continue }
            let thisStart = thisRange[0]
            let thisEnd = thisRange[1]

            for otherRange in other.positions {
                guard otherRange.count >= 2 else { continue }
                let otherStart = otherRange[0]
                let otherEnd = otherRange[1]

                // Check for overlap
                if thisStart < otherEnd && otherStart < thisEnd {
                    return true
                }
            }
        }
        return false
    }

    /// Get all character ranges as Swift ranges
    var ranges: [Range<Int>] {
        return positions.compactMap { pos in
            guard pos.count >= 2 else { return nil }
            return pos[0]..<pos[1]
        }
    }
}

// MARK: - Comparable Conformance

extension Entity: Comparable {
    /// Entities are sorted by their first occurrence position
    static func < (lhs: Entity, rhs: Entity) -> Bool {
        guard let lhsPos = lhs.firstPosition,
              let rhsPos = rhs.firstPosition else {
            return false
        }
        return lhsPos < rhsPos
    }
}

// MARK: - Custom String Convertible

extension Entity: CustomStringConvertible {
    var description: String {
        return "\(type.displayName): '\(originalText)' → '\(replacementCode)' (\(occurrenceCount) occurrence\(occurrenceCount == 1 ? "" : "s"))"
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension Entity {
    /// Sample entity for previews
    static var sample: Entity {
        return Entity(
            originalText: "Jane Smith",
            replacementCode: "[CLIENT_A]",
            type: .personClient,
            positions: [[0, 10], [45, 55]],
            confidence: 0.95
        )
    }

    /// Sample entities for list previews
    static var samples: [Entity] {
        return [
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
                positions: [[30, 40]],
                confidence: 0.98
            ),
            Entity(
                originalText: "March 15, 2024",
                replacementCode: "[DATE_A]",
                type: .date,
                positions: [[60, 74]],
                confidence: 1.0
            ),
            Entity(
                originalText: "Auckland",
                replacementCode: "[LOCATION_A]",
                type: .location,
                positions: [[100, 108]],
                confidence: 0.85
            )
        ]
    }

    /// Entity with low confidence
    static var lowConfidence: Entity {
        return Entity(
            originalText: "Smith",
            replacementCode: "[PERSON_A]",
            type: .personOther,
            positions: [[50, 55]],
            confidence: 0.60
        )
    }

    /// Entity with multiple occurrences
    static var multipleOccurrences: Entity {
        return Entity(
            originalText: "Jane",
            replacementCode: "[CLIENT_A]",
            type: .personClient,
            positions: [[0, 4], [50, 54], [120, 124]],
            confidence: 0.95
        )
    }
}
#endif
