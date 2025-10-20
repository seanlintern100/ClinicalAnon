//
//  NZPhoneRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects NZ phone numbers (mobile, landline, international)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - NZ Phone Recognizer

/// Recognizes New Zealand phone number formats
class NZPhoneRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // NZ Mobile numbers: 021/022/027/029
            // Formats: 021-555-1234, 021 555 1234, 0215551234
            ("\\b0(21|22|27|29)[\\s-]?\\d{3}[\\s-]?\\d{4}\\b", .contact, 0.95),

            // NZ Landline: 03-XXX-XXXX, 04-XXX-XXXX, etc.
            ("\\b0[3-9][\\s-]?\\d{3}[\\s-]?\\d{4}\\b", .contact, 0.9),

            // International format: +64 followed by area code
            // +64 21 555 1234, +64-9-555-1234
            ("\\+64[\\s-]?\\d{1,2}[\\s-]?\\d{3}[\\s-]?\\d{4}\\b", .contact, 0.95),

            // 0800 numbers (freephone)
            ("\\b0800[\\s-]?\\d{3}[\\s-]?\\d{3}\\b", .contact, 0.9)
        ]

        super.init(patterns: patterns)
    }
}
