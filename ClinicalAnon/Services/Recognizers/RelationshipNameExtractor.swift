//
//  RelationshipNameExtractor.swift
//  ClinicalAnon
//
//  Purpose: Extracts names from relationship patterns (e.g., "sister Margaret")
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Relationship Name Extractor

/// Extracts proper names that appear after relationship words
/// Example: "sister Margaret" → extracts "Margaret"
/// Critical for clinical text where relationships are commonly mentioned
class RelationshipNameExtractor: EntityRecognizer {

    // MARK: - Properties

    /// Relationship words that typically precede names
    private let relationshipWords: Set<String> = [
        // Family relationships
        "mother", "father", "sister", "brother", "son", "daughter",
        "grandmother", "grandfather", "grandma", "grandpa",
        "aunt", "uncle", "cousin", "niece", "nephew",
        "stepmother", "stepfather", "stepsister", "stepbrother",

        // Māori/cultural terms
        "whanau", "whangai",

        // Partnerships
        "wife", "husband", "partner", "spouse", "fiance", "fiancee",
        "boyfriend", "girlfriend", "ex-wife", "ex-husband",

        // Social relationships
        "friend", "flatmate", "roommate", "colleague", "coworker",
        "neighbor", "neighbour", "mate", "buddy"
    ]

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        for relationship in relationshipWords {
            // Pattern: relationship word followed by capitalized name(s)
            // Matches:
            // - "sister Margaret"
            // - "mother Sofia"
            // - "friend David Smith"

            let pattern = "\\b\(relationship)\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?)"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                // Get the captured group (the name after relationship word)
                guard match.numberOfRanges > 1,
                      let nameRange = Range(match.range(at: 1), in: text) else {
                    continue
                }

                let name = String(text[nameRange])

                // Skip if it's a common word (not a name)
                guard !isCommonWord(name) else { continue }

                let start = text.distance(from: text.startIndex, to: nameRange.lowerBound)
                let end = text.distance(from: text.startIndex, to: nameRange.upperBound)

                entities.append(Entity(
                    originalText: name,
                    replacementCode: "",
                    type: .personOther,
                    positions: [[start, end]],
                    confidence: 0.9  // High confidence - clear pattern
                ))
            }
        }

        // Also handle list patterns: "sister Margaret, brother John, and friend David"
        entities.append(contentsOf: extractNamesFromLists(in: text))

        return entities
    }

    // MARK: - List Pattern Extraction

    /// Extract names from list patterns
    /// Example: "mother Sofia, sister Rachel, and flatmate David"
    private func extractNamesFromLists(in text: String) -> [Entity] {
        var entities: [Entity] = []

        // Pattern for lists: "relationship Name, relationship Name, and relationship Name"
        // More complex - look for commas and 'and' between relationship+name pairs

        let relationshipPattern = relationshipWords.joined(separator: "|")
        let listPattern = "\\b(\(relationshipPattern))\\s+([A-Z][a-z]+)"

        guard let regex = try? NSRegularExpression(pattern: listPattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let name = String(text[nameRange])

            guard !isCommonWord(name) else { continue }

            let start = text.distance(from: text.startIndex, to: nameRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: nameRange.upperBound)

            entities.append(Entity(
                originalText: name,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.85  // Slightly lower confidence for list extraction
            ))
        }

        return entities
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension RelationshipNameExtractor {
    /// Test with sample relationship patterns
    static func testExtraction() -> [Entity] {
        let extractor = RelationshipNameExtractor()

        let testText = """
        Client lives with mother Sofia, sister Rachel, and flatmate David.
        His brother John visits occasionally.
        Friend Margaret called to check in.
        He is close with his grandmother Aroha.
        """

        return extractor.recognize(in: testText)
    }
}
#endif
