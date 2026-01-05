//
//  DateNormalizer.swift
//  ClinicalAnon
//
//  Purpose: Normalizes dates to consistent dd/MM/yyyy format during restore
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Date Normalizer

/// Utility for normalizing dates to a consistent format (dd/MM/yyyy)
struct DateNormalizer {

    // MARK: - Configuration

    /// Output format for normalized dates
    static let outputFormat = "dd/MM/yyyy"

    /// Patterns to recognize (in order of specificity)
    private static let inputPatterns: [(pattern: String, format: String)] = [
        // Long formats with full month names
        ("\\d{1,2}\\s+(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{4}", "d MMMM yyyy"),
        ("(January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},?\\s+\\d{4}", "MMMM d, yyyy"),

        // Short month names
        ("\\d{1,2}\\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{4}", "d MMM yyyy"),
        ("(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{1,2},?\\s+\\d{4}", "MMM d, yyyy"),

        // ISO format
        ("\\d{4}-\\d{2}-\\d{2}", "yyyy-MM-dd"),

        // Common slash formats (be careful with ambiguity)
        ("\\d{1,2}/\\d{1,2}/\\d{4}", "dd/MM/yyyy"),  // Prefer AU/UK format

        // Two-digit year formats
        ("\\d{1,2}/\\d{1,2}/\\d{2}", "dd/MM/yy"),
    ]

    // MARK: - Public Methods

    /// Normalize a single date string to dd/MM/yyyy format
    /// - Parameter dateString: The date string to normalize
    /// - Returns: Normalized date string, or original if parsing fails
    static func normalize(_ dateString: String) -> String {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try each input format
        for (_, format) in inputPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = format

            if let date = formatter.date(from: trimmed) {
                let outputFormatter = DateFormatter()
                outputFormatter.locale = Locale(identifier: "en_AU")
                outputFormatter.dateFormat = outputFormat
                return outputFormatter.string(from: date)
            }
        }

        // Try alternative parsing for edge cases
        if let date = parseFlexible(trimmed) {
            let outputFormatter = DateFormatter()
            outputFormatter.locale = Locale(identifier: "en_AU")
            outputFormatter.dateFormat = outputFormat
            return outputFormatter.string(from: date)
        }

        // Return original if no format matched
        return dateString
    }

    /// Find and normalize all dates in a text
    /// - Parameter text: Text containing dates to normalize
    /// - Returns: Text with all recognized dates normalized to dd/MM/yyyy
    static func normalizeAllDates(in text: String) -> String {
        var result = text

        // Process patterns from longest to shortest to avoid partial replacements
        for (pattern, format) in inputPatterns.sorted(by: { $0.pattern.count > $1.pattern.count }) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: nsRange)

            // Process matches in reverse order to maintain string indices
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let dateString = String(result[range])

                // Parse with this specific format
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_AU")
                formatter.dateFormat = format

                if let date = formatter.date(from: dateString) {
                    let outputFormatter = DateFormatter()
                    outputFormatter.locale = Locale(identifier: "en_AU")
                    outputFormatter.dateFormat = outputFormat
                    let normalized = outputFormatter.string(from: date)

                    result.replaceSubrange(range, with: normalized)

                    #if DEBUG
                    if normalized != dateString {
                        print("DateNormalizer: '\(dateString)' → '\(normalized)'")
                    }
                    #endif
                }
            }
        }

        return result
    }

    // MARK: - Private Methods

    /// Flexible date parsing for edge cases
    private static func parseFlexible(_ string: String) -> Date? {
        // Try natural language date parsing
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(string.startIndex..., in: string)

        if let match = detector?.firstMatch(in: string, options: [], range: range) {
            return match.date
        }

        return nil
    }

    /// Check if a string looks like a date
    static func looksLikeDate(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check against known patterns
        for (pattern, _) in inputPatterns {
            if let regex = try? NSRegularExpression(pattern: "^\(pattern)$", options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension DateNormalizer {
    /// Test date normalization with various formats
    static func testNormalization() {
        let testDates = [
            "12 January 2024",
            "January 12, 2024",
            "2024-01-12",
            "12/01/2024",
            "12/1/24",
            "12 Jan 2024",
            "Jan 12, 2024",
        ]

        print("DateNormalizer Test Results:")
        print("Output format: \(outputFormat)")
        print("---")

        for date in testDates {
            let normalized = normalize(date)
            let marker = normalized != date ? "✓" : "="
            print("\(marker) '\(date)' → '\(normalized)'")
        }
    }

    /// Test normalizing dates in text
    static func testTextNormalization() {
        let text = """
        Patient visited on 12 January 2024.
        Follow-up scheduled for January 15, 2024.
        Previous appointment was 2023-12-01.
        """

        print("\nOriginal text:")
        print(text)
        print("\nNormalized text:")
        print(normalizeAllDates(in: text))
    }
}
#endif
