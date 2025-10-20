//
//  MaoriNameRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects Māori names using dictionary lookup and phonetic patterns
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Māori Name Recognizer

/// Recognizes Māori names through:
/// 1. Dictionary lookup (high confidence)
/// 2. Phonetic pattern matching (lower confidence)
class MaoriNameRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Common Māori first names
    private static let firstNames: Set<String> = [
        // Male names
        "Wiremu", "Hemi", "Pita", "Rawiri", "Mikaere", "Tane", "Rangi",
        "Tamati", "Hohepa", "Aperahama", "Timoti", "Hone", "Paora",

        // Female names
        "Aroha", "Kiri", "Mere", "Hana", "Anahera", "Moana", "Ngaire",
        "Whetu", "Kahu", "Ataahua", "Hinewai", "Hine", "Marama", "Ariana",

        // Gender-neutral names
        "Rangi", "Tane", "Kahu", "Moana"
    ]

    /// Common Māori surnames and second names
    private static let lastNames: Set<String> = [
        "Ngata", "Te Ao", "Tawhiri", "Wairua", "Takiri",
        "Parata", "Ngati", "Whaanga", "Eruera"
    ]

    /// Pattern for Māori phonetic features:
    /// - Words with 'wh' or 'ng' clusters
    /// - High vowel density
    /// - Capitaliz words (proper nouns)
    private let maoriPhoneticPattern = "\\b[A-Z][a-z]*(?:wh|ng)[a-z]+|\\b[A-Z][aeiouAEIOU]{2,}[a-z]*\\b"

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        // 1. Dictionary lookup (high confidence)
        entities.append(contentsOf: recognizeKnownNames(in: text))

        // 2. Phonetic pattern matching (lower confidence)
        entities.append(contentsOf: recognizePhoneticPatterns(in: text))

        return entities
    }

    // MARK: - Dictionary Lookup

    /// Recognize known Māori names from dictionary
    private func recognizeKnownNames(in text: String) -> [Entity] {
        var entities: [Entity] = []

        // Split into words
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var currentPosition = 0

        for word in words {
            // Clean punctuation
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)

            // Check if it's a known Māori name
            if Self.firstNames.contains(cleanWord) || Self.lastNames.contains(cleanWord) {
                // Find actual position in text
                if let range = text.range(of: cleanWord, range: text.index(text.startIndex, offsetBy: currentPosition)..<text.endIndex) {
                    let start = text.distance(from: text.startIndex, to: range.lowerBound)
                    let end = text.distance(from: text.startIndex, to: range.upperBound)

                    entities.append(Entity(
                        originalText: cleanWord,
                        replacementCode: "",
                        type: .personOther,
                        positions: [[start, end]],
                        confidence: 0.95  // High confidence for known names
                    ))
                }
            }

            currentPosition += word.count + 1  // +1 for space
        }

        return entities
    }

    // MARK: - Phonetic Pattern Matching

    /// Recognize potential Māori names by phonetic patterns
    private func recognizePhoneticPatterns(in text: String) -> [Entity] {
        guard let regex = try? NSRegularExpression(pattern: maoriPhoneticPattern) else {
            return []
        }

        var entities: [Entity] = []
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }

            let word = String(text[range])

            // Filter out common English words that happen to match pattern
            guard !isCommonEnglishWord(word) else { continue }

            // Skip if already in our dictionary (will be caught by dictionary lookup)
            guard !Self.firstNames.contains(word) && !Self.lastNames.contains(word) else {
                continue
            }

            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)

            entities.append(Entity(
                originalText: word,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.6  // Lower confidence for pattern matching
            ))
        }

        return entities
    }

    // MARK: - Helpers

    /// Check if word is a common English word that matches Māori patterns
    private func isCommonEnglishWord(_ word: String) -> Bool {
        let falsePositives: Set<String> = [
            "Where", "When", "What", "Thing", "Something", "Anything",
            "Whither", "Whether", "Whence"
        ]

        return falsePositives.contains(word)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension MaoriNameRecognizer {
    /// Test with sample Māori names
    static func testRecognition() -> [Entity] {
        let recognizer = MaoriNameRecognizer()

        let testText = """
        Wiremu attended his appointment with Aroha and Hemi.
        His sister Mere also came along with friend Kiri.
        Contact person: Ngaire Tawhiri
        """

        return recognizer.recognize(in: testText)
    }
}
#endif
