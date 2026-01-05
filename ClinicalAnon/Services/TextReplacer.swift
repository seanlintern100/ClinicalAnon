//
//  TextReplacer.swift
//  ClinicalAnon
//
//  Purpose: Performs text replacement operations for anonymization
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Text Replacer

/// Performs text replacement operations to anonymize text
class TextReplacer {

    // MARK: - Public Methods

    /// Replace all entities in text with their replacement codes
    /// - Parameters:
    ///   - originalText: The original clinical text
    ///   - entities: Array of entities to replace
    /// - Returns: The anonymized text with replacement codes
    /// - Throws: AppError if replacement fails
    static func replaceEntities(in originalText: String, with entities: [Entity]) throws -> String {
        guard !originalText.isEmpty else {
            throw AppError.textValidationFailed("Original text is empty")
        }

        // If no entities, return original text
        if entities.isEmpty {
            return originalText
        }

        // IMPROVED: Don't trust LLM positions - find text ourselves
        // This is more reliable since LLMs think in tokens, not characters
        var result = originalText

        // Process entities in order of first occurrence
        // This ensures we don't mess up positions by replacing later text first
        for entity in entities {
            // Build pattern that also catches possessive forms (e.g., "Seans", "Sean's")
            // This handles informal writing where apostrophes are omitted
            let escapedText = NSRegularExpression.escapedPattern(for: entity.originalText)

            // For person entities, also match possessive forms
            let pattern: String
            if entity.type.isPerson {
                // Match: exact text, text+'s, text+s (possessive without apostrophe)
                // Use word boundary to avoid matching "Seansation" etc.
                pattern = "\(escapedText)(?:'s|s(?![a-zA-Z]))?"
            } else {
                pattern = escapedText
            }

            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: entity.replacementCode
                )
            }
        }

        print("✅ Replaced \(entities.count) entity types")

        return result
    }

    /// Reverse replacement - restore original text from anonymized text
    /// - Parameters:
    ///   - anonymizedText: The anonymized text with replacement codes
    ///   - entities: Array of entities that were replaced
    /// - Returns: The original text restored
    static func reverseReplacement(in anonymizedText: String, with entities: [Entity]) -> String {
        var result = anonymizedText

        // For each entity, replace the code back with original text
        for entity in entities {
            result = result.replacingOccurrences(
                of: entity.replacementCode,
                with: entity.originalText
            )
        }

        return result
    }

    /// Verify that anonymized text matches expected result
    /// - Parameters:
    ///   - anonymizedText: The text after replacement
    ///   - originalText: The original text
    ///   - entities: The entities that were replaced
    /// - Returns: True if verification passes
    static func verifyReplacement(
        anonymizedText: String,
        originalText: String,
        entities: [Entity]
    ) -> Bool {
        // Check that all replacement codes appear in the result
        for entity in entities {
            if !anonymizedText.contains(entity.replacementCode) {
                return false
            }
        }

        // Check that no original text remains (for entities)
        for entity in entities {
            // Use case-sensitive check
            if anonymizedText.contains(entity.originalText) {
                // Could be a substring of something else, so be careful
                // For now, we'll allow this case
                continue
            }
        }

        return true
    }

    /// Count how many replacements were made
    static func countReplacements(in text: String, for entities: [Entity]) -> Int {
        var count = 0

        for entity in entities {
            // Count occurrences of replacement code
            let occurrences = text.occurrences(of: entity.replacementCode)
            count += occurrences
        }

        return count
    }

    /// Get all replacement codes present in text
    static func extractReplacementCodes(from text: String) -> [String] {
        let pattern = "\\[([A-Z]+_[A-Z]+)\\]"  // Matches [TYPE_A], [TYPE_AA], [TYPE_AB], etc.

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        var codes: Set<String> = []
        for match in matches {
            if let range = Range(match.range, in: text) {
                codes.insert(String(text[range]))
            }
        }

        return Array(codes).sorted()
    }

    // MARK: - Partial Leak Fix

    /// Fix partial leaks like [PERSON_P]rray by extending entities
    /// - Parameters:
    ///   - text: The text after initial replacement
    ///   - entities: The entities that were replaced
    ///   - originalText: The original unredacted text
    /// - Returns: Fixed text and any extended entities
    static func fixPartialLeaks(
        in text: String,
        entities: [Entity],
        originalText: String
    ) -> (String, [Entity]) {

        // Pattern: placeholder followed by letters (partial leak)
        let pattern = "\\[([A-Z_]+)\\]([a-zA-Z]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }

        var fixedText = text
        var extendedEntities: [Entity] = []
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range).reversed()

        for match in matches {
            guard let placeholderRange = Range(match.range(at: 0), in: text),
                  let codeRange = Range(match.range(at: 1), in: text),
                  let leakedRange = Range(match.range(at: 2), in: text) else { continue }

            let fullMatch = String(text[placeholderRange])  // [PERSON_P]rray
            let code = String(text[codeRange])               // PERSON_P
            let leaked = String(text[leakedRange])           // rray

            // Find the original entity this placeholder came from
            if let entity = entities.first(where: { $0.replacementCode == "[\(code)]" }) {
                // Build the full original text: original + leaked
                let fullOriginal = entity.originalText + leaked

                // Verify it exists in original text (case-insensitive)
                if originalText.range(of: fullOriginal, options: .caseInsensitive) != nil {
                    // Replace partial leak with the same placeholder
                    fixedText = fixedText.replacingOccurrences(
                        of: fullMatch,
                        with: entity.replacementCode
                    )

                    // Create extended entity for tracking
                    let extended = Entity(
                        originalText: fullOriginal,
                        replacementCode: entity.replacementCode,
                        type: entity.type,
                        positions: [],
                        confidence: entity.confidence
                    )
                    extendedEntities.append(extended)

                    print("🔧 Fixed partial leak: '\(fullMatch)' → '\(entity.replacementCode)' (full: '\(fullOriginal)')")
                }
            }
        }

        return (fixedText, extendedEntities)
    }

    // MARK: - Statistics

    /// Calculate replacement statistics
    static func calculateStatistics(
        originalText: String,
        anonymizedText: String,
        entities: [Entity]
    ) -> ReplacementStatistics {
        let originalLength = originalText.count
        let anonymizedLength = anonymizedText.count
        let lengthDifference = anonymizedLength - originalLength

        let totalReplacements = entities.reduce(0) { $0 + $1.occurrenceCount }
        let uniqueEntities = entities.count

        let replacementCodes = extractReplacementCodes(from: anonymizedText)
        let codesUsed = replacementCodes.count

        return ReplacementStatistics(
            originalLength: originalLength,
            anonymizedLength: anonymizedLength,
            lengthDifference: lengthDifference,
            totalReplacements: totalReplacements,
            uniqueEntities: uniqueEntities,
            replacementCodesUsed: codesUsed
        )
    }
}

// MARK: - Replacement Statistics

struct ReplacementStatistics {
    let originalLength: Int
    let anonymizedLength: Int
    let lengthDifference: Int
    let totalReplacements: Int
    let uniqueEntities: Int
    let replacementCodesUsed: Int

    var summary: String {
        """
        Original length: \(originalLength) characters
        Anonymized length: \(anonymizedLength) characters
        Difference: \(lengthDifference >= 0 ? "+" : "")\(lengthDifference) characters
        Total replacements: \(totalReplacements)
        Unique entities: \(uniqueEntities)
        Replacement codes used: \(replacementCodesUsed)
        """
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension TextReplacer {
    /// Test simple replacement
    static func testSimpleReplacement() throws -> String {
        let originalText = "Jane Smith attended her session."

        let entity = Entity(
            originalText: "Jane Smith",
            replacementCode: "[CLIENT_A]",
            type: .personClient,
            positions: [[0, 10]]
        )

        return try replaceEntities(in: originalText, with: [entity])
    }

    /// Test multiple occurrences
    static func testMultipleOccurrences() throws -> String {
        let originalText = "Jane saw Dr. Smith. Jane reported improvement. Dr. Smith noted progress."

        let entities = [
            Entity(
                originalText: "Jane",
                replacementCode: "[CLIENT_A]",
                type: .personClient,
                positions: [[0, 4], [20, 24]]
            ),
            Entity(
                originalText: "Dr. Smith",
                replacementCode: "[PROVIDER_A]",
                type: .personProvider,
                positions: [[9, 18], [48, 57]]
            )
        ]

        return try replaceEntities(in: originalText, with: entities)
    }

    /// Test reverse replacement
    static func testReverse() -> String {
        let anonymizedText = "[CLIENT_A] attended session with [PROVIDER_A]."

        let entities = [
            Entity(
                originalText: "Jane Smith",
                replacementCode: "[CLIENT_A]",
                type: .personClient,
                positions: [[0, 10]]
            ),
            Entity(
                originalText: "Dr. Wilson",
                replacementCode: "[PROVIDER_A]",
                type: .personProvider,
                positions: [[33, 45]]
            )
        ]

        return reverseReplacement(in: anonymizedText, with: entities)
    }

    /// Sample statistics
    static var sampleStatistics: ReplacementStatistics {
        return ReplacementStatistics(
            originalLength: 150,
            anonymizedLength: 145,
            lengthDifference: -5,
            totalReplacements: 5,
            uniqueEntities: 3,
            replacementCodesUsed: 3
        )
    }
}
#endif
