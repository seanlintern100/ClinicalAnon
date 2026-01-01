//
//  TitleNameRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Extracts names following titles (Mr, Mrs, Dr, etc.)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Title Name Recognizer

/// Extracts proper names that appear after titles
/// Example: "Mr Ronald Praneer Nath" → extracts "Ronald Praneer Nath"
/// Critical for detecting full names that Apple NER fragments incorrectly
class TitleNameRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Titles that typically precede names
    private let titles: [String] = [
        "Mr", "Mrs", "Ms", "Miss", "Dr", "Prof",
        "Pastor", "Reverend", "Rev", "Father", "Fr",
        "Sir", "Dame", "Lord", "Lady"
    ]

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        // Build pattern: Title (with optional period) + 1-3 capitalized words
        let titlePattern = titles.joined(separator: "|")
        // Pattern matches: "Mr Ronald", "Dr. John Smith", "Mrs Jane Anne Doe"
        let pattern = "\\b(\(titlePattern))\\.?\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+){0,2})"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            // Get the captured group (the name after title)
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let name = String(text[nameRange])

            // Skip if it's a common word (not a name)
            guard !isCommonWord(name) else { continue }

            // Skip user-excluded words
            guard !isUserExcluded(name) else { continue }

            let start = text.distance(from: text.startIndex, to: nameRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: nameRange.upperBound)

            entities.append(Entity(
                originalText: name,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.9  // High confidence - title provides clear context
            ))
        }

        return entities
    }
}
