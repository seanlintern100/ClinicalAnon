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
    /// - Returns: Text with real names restored
    func restore(text: String, using mapping: EntityMapping) -> String {
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

        #if DEBUG
        print("🔄 TextReidentifier: Restoring \(sorted.count) placeholders")
        #endif

        // Replace each placeholder with original text
        for mapping in sorted {
            let occurrences = result.occurrences(of: mapping.placeholder)
            if occurrences > 0 {
                result = result.replacingOccurrences(
                    of: mapping.placeholder,
                    with: mapping.original
                )
                #if DEBUG
                print("  ✓ Replaced \(mapping.placeholder) → '\(mapping.original)' (\(occurrences) times)")
                #endif
            }
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
