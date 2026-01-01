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
        let nsText = text as NSString

        // Combine all known names and search using word boundary regex
        let allNames = Self.firstNames.union(Self.lastNames)

        for name in allNames {
            // Skip user-excluded names
            guard !isUserExcluded(name) else { continue }

            // Use word boundary regex to find all occurrences
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = "\\b\(escapedName)\\b"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let searchRange = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, options: [], range: searchRange)

            for match in matches {
                // Use NSRange directly for UTF-16 positions
                let start = match.range.location
                let end = match.range.location + match.range.length
                let matchedText = nsText.substring(with: match.range)

                entities.append(Entity(
                    originalText: matchedText,
                    replacementCode: "",
                    type: .personOther,
                    positions: [[start, end]],
                    confidence: 0.95  // High confidence for known names
                ))
            }
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
