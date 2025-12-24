//
//  MaoriNameRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects Māori names using dictionary lookup and phonetic patterns
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Māori Name Recognizer

/// Recognizes Māori names through dictionary lookup only
/// Note: Phonetic pattern matching removed due to too many false positives
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

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        // Dictionary lookup only (phonetic pattern removed - too many false positives)
        return recognizeKnownNames(in: text)
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

            // Check if it's a known Māori name (and not user-excluded)
            if (Self.firstNames.contains(cleanWord) || Self.lastNames.contains(cleanWord)) && !isUserExcluded(cleanWord) {
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
