//
//  NZMedicalIDRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects NZ medical identifiers (NHI, ACC case numbers, etc.)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - NZ Medical ID Recognizer

/// Recognizes New Zealand medical identifiers and alphanumeric codes
class NZMedicalIDRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // NHI (National Health Index): 3 letters + 4 digits
            // Example: ABC1234, XYZ5678
            // Note: First letter is always A-Z, second/third can be any letter
            ("\\b[A-Z]{3}\\d{4}\\b", .identifier, 0.85),

            // ACC case numbers
            // Format: ACC followed by 5+ digits
            ("\\bACC\\s?\\d{5,}\\b", .identifier, 0.9),

            // Generic medical record numbers
            // MRN 12345, Case #67890, ID: 12345
            ("\\b(?:MRN|Case|ID)\\s*[:#]?\\s*[A-Z0-9-]{4,}\\b", .identifier, 0.8),

            // Medical record with prefix
            // Format: MR-123456, CR-456789
            ("\\b(?:MR|CR|UR)-\\d{5,}\\b", .identifier, 0.85),

            // CATCH-ALL: Any alphanumeric code containing BOTH letters AND numbers
            // Uses lookaheads to ensure at least one letter and one digit
            // Examples: S7798120001, VEND-G0M136, ABC123, 123ABC, A1B2C3
            // Minimum 4 chars to reduce false positives
            ("(?=[A-Za-z0-9-]*[A-Za-z])(?=[A-Za-z0-9-]*[0-9])[A-Za-z0-9][A-Za-z0-9-]{2,}[A-Za-z0-9]", .identifier, 0.7)
        ]

        super.init(patterns: patterns)
    }
}
