//
//  AllNumbersRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Catches all numeric values not handled by specific recognizers
//  Organization: 3 Big Things
//

import Foundation

// MARK: - All Numbers Recognizer

/// Recognizes all numeric sequences regardless of their purpose.
/// Catches numbers that specific recognizers (dates, phones, IDs) might miss.
/// Uses lower confidence so specific recognizers take precedence.
class AllNumbersRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // Multi-digit numbers with optional separators
            // Matches: 123456, 12-34-56, 12/34/56, 1,234, 12.34
            ("\\b\\d{2,}(?:[/\\-.,]\\d+)*\\b", .numericAll, 0.75),

            // Numbers with spaces (like phone-style: 021 555 1234)
            ("\\b\\d{2,}(?:\\s\\d+)+\\b", .numericAll, 0.75),

            // Single digit followed by more digits with any separator
            ("\\b\\d[/\\-]\\d+(?:[/\\-]\\d+)*\\b", .numericAll, 0.75),

            // Standalone 4+ digit numbers (catches years, case numbers, amounts)
            ("\\b\\d{4,}\\b", .numericAll, 0.7)
        ]

        super.init(patterns: patterns)
    }
}
