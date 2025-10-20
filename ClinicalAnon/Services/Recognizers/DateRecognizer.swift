//
//  DateRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects dates in various formats
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Date Recognizer

/// Recognizes dates in multiple formats common in NZ clinical text
class DateRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // DD/MM/YYYY (NZ standard format)
            // 15/03/2024, 01/12/2023
            ("\\b\\d{1,2}/\\d{1,2}/\\d{4}\\b", .date, 0.95),

            // DD-MM-YYYY
            // 15-03-2024, 01-12-2023
            ("\\b\\d{1,2}-\\d{1,2}-\\d{4}\\b", .date, 0.95),

            // YYYY-MM-DD (ISO format)
            // 2024-03-15
            ("\\b\\d{4}-\\d{1,2}-\\d{1,2}\\b", .date, 0.95),

            // Month DD, YYYY (written format)
            // "March 15, 2024", "June 3, 2023"
            ("\\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{1,2},?\\s+\\d{4}\\b", .date, 0.95),

            // DD Month YYYY (alternative written format)
            // "15 March 2024", "3 June 2023"
            ("\\b\\d{1,2}\\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\\s+\\d{4}\\b", .date, 0.95),

            // Short month format: DD Mon YYYY
            // "15 Mar 2024", "03 Jun 2023"
            ("\\b\\d{1,2}\\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s+\\d{4}\\b", .date, 0.9),

            // Year only (lower confidence - might be other numbers)
            // "2020", "2023"
            ("\\b(?:19|20)\\d{2}\\b", .date, 0.5)
        ]

        super.init(patterns: patterns)
    }
}
