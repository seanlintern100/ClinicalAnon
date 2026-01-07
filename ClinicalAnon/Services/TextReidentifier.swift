//
//  TextReidentifier.swift
//  ClinicalAnon
//
//  Purpose: Reverses redaction by replacing placeholders with original text
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Text Reidentifier

/// Service that reverses anonymization by replacing placeholders with original text
@MainActor
class TextReidentifier {

    // MARK: - Public Methods

    /// Replace all placeholders with original text
    /// - Parameters:
    ///   - text: Text containing placeholders like [PERSON_A]
    ///   - mapping: EntityMapping with placeholder → original mappings
    ///   - normalizeDates: Whether to normalize dates to dd/MM/yyyy format (default: true)
    /// - Returns: Text with real names restored
    func restore(text: String, using mapping: EntityMapping, normalizeDates: Bool = true) -> String {
        var result = text

        // Get all mappings from EntityMapping
        let allMappings = mapping.allMappings

        // Create reverse mapping: [PERSON_A] → "John"
        let reverseMappings = allMappings.map {
            (placeholder: $0.replacement, original: $0.original)
        }

        // Sort by placeholder length (longest first to avoid partial replacements)
        // Example: [PERSON_AB] should be replaced before [PERSON_A]
        let sorted = reverseMappings.sorted { $0.placeholder.count > $1.placeholder.count }

        // Replace each placeholder with original text
        for mapping in sorted {
            // Skip if original is empty - leave placeholder in text for user to fill in
            // This handles AI-generated placeholders that have no original text
            guard !mapping.original.isEmpty else { continue }

            // For date placeholders, also match trailing year if present
            // This handles keepYear format: "[DATE_A] 1978" → "18/05/1978"
            if mapping.placeholder.contains("DATE") {
                let escapedPlaceholder = NSRegularExpression.escapedPattern(for: mapping.placeholder)
                let pattern = escapedPlaceholder + "(\\s+(19|20)\\d{2})?"

                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: mapping.original)
                }
            } else {
                let occurrences = result.occurrences(of: mapping.placeholder)
                if occurrences > 0 {
                    result = result.replacingOccurrences(
                        of: mapping.placeholder,
                        with: mapping.original
                    )
                }
            }
        }

        // Normalize dates to dd/MM/yyyy format
        if normalizeDates {
            result = DateNormalizer.normalizeAllDates(in: result)
        }

        return result
    }

    /// Replace all placeholders with original text, using overrides where specified
    /// - Parameters:
    ///   - text: Text containing placeholders like [PERSON_A]
    ///   - mapping: EntityMapping with placeholder → original mappings
    ///   - overrides: Dictionary of [replacementCode: customText] for manual edits
    ///   - normalizeDates: Whether to normalize dates to dd/MM/yyyy format (default: true)
    /// - Returns: Text with names restored, using overrides where available
    func restoreWithOverrides(text: String, using mapping: EntityMapping, overrides: [String: String], normalizeDates: Bool = true) -> String {
        var result = text

        // Get all mappings from EntityMapping
        let allMappings = mapping.allMappings

        // Create reverse mapping: [PERSON_A] → "John" (or override if exists)
        let reverseMappings = allMappings.map { mapping -> (placeholder: String, original: String) in
            let replacement = overrides[mapping.replacement] ?? mapping.original
            return (placeholder: mapping.replacement, original: replacement)
        }

        // Sort by placeholder length (longest first to avoid partial replacements)
        let sorted = reverseMappings.sorted { $0.placeholder.count > $1.placeholder.count }

        // Replace each placeholder with original/override text
        for mapping in sorted {
            // Skip if replacement is empty - leave placeholder in text for user to fill in
            // This handles AI-generated placeholders that have no original text and no override yet
            guard !mapping.original.isEmpty else { continue }

            // For date placeholders, also match trailing year if present
            // This handles keepYear format: "[DATE_A] 1978" → "18/05/1978"
            if mapping.placeholder.contains("DATE") {
                let escapedPlaceholder = NSRegularExpression.escapedPattern(for: mapping.placeholder)
                let pattern = escapedPlaceholder + "(\\s+(19|20)\\d{2})?"

                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: mapping.original)
                }
            } else {
                let occurrences = result.occurrences(of: mapping.placeholder)
                if occurrences > 0 {
                    result = result.replacingOccurrences(
                        of: mapping.placeholder,
                        with: mapping.original
                    )
                }
            }
        }

        // Second pass: Apply overrides for placeholders NOT in the mapping
        // This handles AI-generated placeholders that user has provided replacement text for
        let mappedPlaceholders = Set(allMappings.map { $0.replacement })
        for (placeholder, customText) in overrides where !mappedPlaceholders.contains(placeholder) {
            // Only replace if custom text is not empty
            guard !customText.isEmpty else { continue }
            result = result.replacingOccurrences(of: placeholder, with: customText)
        }

        // Normalize dates to dd/MM/yyyy format
        if normalizeDates {
            result = DateNormalizer.normalizeAllDates(in: result)
        }

        return result
    }

    /// Preview what placeholders will be replaced
    /// Useful for showing user what changes will be made before restoring
    /// - Parameters:
    ///   - text: Text to analyze
    ///   - mapping: EntityMapping to use
    /// - Returns: Array of (placeholder, original text, count) tuples
    func previewReplacements(in text: String, using mapping: EntityMapping) -> [(placeholder: String, original: String, count: Int)] {
        var previews: [(placeholder: String, original: String, count: Int)] = []

        for (original, replacement) in mapping.allMappings {
            let count = text.occurrences(of: replacement)
            if count > 0 {
                previews.append((placeholder: replacement, original: original, count: count))
            }
        }

        return previews.sorted { $0.placeholder < $1.placeholder }
    }

    /// Validate that text contains expected placeholders
    /// - Parameters:
    ///   - text: Text to validate
    ///   - mapping: EntityMapping to check against
    /// - Returns: Array of missing placeholders that were expected
    func validatePlaceholders(in text: String, using mapping: EntityMapping) -> [String] {
        var missing: [String] = []

        for (_, replacement) in mapping.allMappings {
            if !text.contains(replacement) {
                missing.append(replacement)
            }
        }

        return missing
    }

}

// MARK: - Preview Helpers

#if DEBUG
extension TextReidentifier {
    /// Test restoring with sample data
    static func testRestore() {
        let reidentifier = TextReidentifier()
        let mapping = EntityMapping.sample

        let redactedText = """
        [CLIENT_A] visited [PROVIDER_A] on [DATE_A].
        The appointment at [LOCATION_A] went well.
        [CLIENT_A] will return next week.
        """

        let restored = reidentifier.restore(text: redactedText, using: mapping)
        print("Restored text:")
        print(restored)

        let preview = reidentifier.previewReplacements(in: redactedText, using: mapping)
        print("\nPreviewed replacements:")
        for (placeholder, original, count) in preview {
            print("  \(placeholder) → '\(original)' (\(count) times)")
        }
    }
}
#endif
