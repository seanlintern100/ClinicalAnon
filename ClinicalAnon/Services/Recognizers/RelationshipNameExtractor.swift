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
        let nsText = text as NSString

        for relationship in relationshipWords {
            // Pattern: relationship word (case-insensitive) followed by capitalized name(s)
            // Matches:
            // - "sister Margaret"
            // - "mother Sofia"
            // - "friend David Smith"
            // Note: We use (?i) for case-insensitive relationship word only,
            // but require actual uppercase for names to avoid false positives like "mother checks"

            let pattern = "(?i)\\b\(relationship)(?-i)\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?)"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                // Get the captured group (the name after relationship word)
                guard match.numberOfRanges > 1 else { continue }

                let nameNSRange = match.range(at: 1)
                guard nameNSRange.location != NSNotFound else { continue }

                // Use NSString for UTF-16 consistent substring
                let name = nsText.substring(with: nameNSRange)

                // Skip if it's a common word (not a name)
                guard !isCommonWord(name) else { continue }

                // Use NSRange directly for UTF-16 positions
                let start = nameNSRange.location
                let end = nameNSRange.location + nameNSRange.length

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
        let nsText = text as NSString

        // Pattern for lists: "relationship Name, relationship Name, and relationship Name"
        // More complex - look for commas and 'and' between relationship+name pairs
        // Note: (?i) for case-insensitive relationship word, (?-i) to require uppercase names

        let relationshipPattern = relationshipWords.joined(separator: "|")
        let listPattern = "(?i)\\b(\(relationshipPattern))(?-i)\\s+([A-Z][a-z]+)"

        guard let regex = try? NSRegularExpression(pattern: listPattern, options: []) else {
            return []
        }

        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard match.numberOfRanges > 2 else { continue }

            let nameNSRange = match.range(at: 2)
            guard nameNSRange.location != NSNotFound else { continue }

            // Use NSString for UTF-16 consistent substring
            let name = nsText.substring(with: nameNSRange)

            guard !isCommonWord(name) else { continue }

            // Use NSRange directly for UTF-16 positions
            let start = nameNSRange.location
            let end = nameNSRange.location + nameNSRange.length

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
