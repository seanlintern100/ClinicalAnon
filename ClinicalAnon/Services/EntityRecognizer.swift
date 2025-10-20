//
//  EntityRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Protocol for entity recognition implementations
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Recognizer Protocol

/// Protocol for all entity recognizers
/// Each recognizer scans text and returns detected entities
protocol EntityRecognizer {
    /// Recognize entities in the given text
    /// - Parameter text: The text to scan for entities
    /// - Returns: Array of detected entities
    func recognize(in text: String) -> [Entity]
}

// MARK: - Pattern Recognizer Base Class

/// Base class for regex-based entity recognizers
/// Subclass and provide patterns to implement specific recognizers
class PatternRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Array of (pattern, entityType, confidence) tuples
    let patterns: [(pattern: String, type: EntityType, confidence: Double)]

    // MARK: - Initialization

    init(patterns: [(String, EntityType, Double)]) {
        self.patterns = patterns
    }

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        for (pattern, type, confidence) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                print("⚠️ Invalid regex pattern: \(pattern)")
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }

                let matched = String(text[range])
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)

                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "", // Will be assigned by EntityMapping
                    type: type,
                    positions: [[start, end]],
                    confidence: confidence
                ))
            }
        }

        return entities
    }
}

// MARK: - Helper Extensions

extension EntityRecognizer {
    /// Helper to find all occurrences of a word in text
    func findOccurrences(of word: String, in text: String, caseInsensitive: Bool = false) -> [[Int]] {
        var positions: [[Int]] = []
        var searchRange = text.startIndex..<text.endIndex

        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []

        while let range = text.range(of: word, options: options, range: searchRange) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            positions.append([start, end])

            searchRange = range.upperBound..<text.endIndex
        }

        return positions
    }

    /// Check if a word is a common English word to exclude
    func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            // Articles
            "the", "a", "an",
            // Conjunctions
            "and", "but", "or", "nor", "for", "yet", "so",
            // Prepositions
            "in", "on", "at", "to", "from", "with", "by", "for", "of", "about",
            // Pronouns
            "he", "she", "it", "they", "we", "you", "i",
            "him", "her", "them", "us", "me",
            "his", "her", "its", "their", "our", "your", "my",
            // Common verbs
            "is", "was", "are", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            // Other common words
            "this", "that", "these", "those",
            "when", "where", "what", "which", "who", "why", "how",
            // Medical/clinical common words
            "patient", "treatment", "therapy", "care", "health",
            "medical", "clinical", "hospital", "clinic", "doctor",
            // Relationship words (already filtered by RelationshipNameExtractor)
            "mother", "father", "sister", "brother", "son", "daughter",
            "wife", "husband", "partner", "friend", "family", "whanau"
        ]

        return commonWords.contains(word.lowercased())
    }
}
