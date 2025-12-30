//
//  EmailRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Recognizes email addresses for redaction
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Email Recognizer

/// Recognizes email addresses in clinical text.
/// Uses high confidence (0.95) to take precedence over LLM detection which may truncate emails.
class EmailRecognizer: PatternRecognizer {

    init() {
        let patterns: [(String, EntityType, Double)] = [
            // Standard email pattern - handles most email formats including:
            // - user@domain.com
            // - user.name@domain.co.nz
            // - user+tag@sub.domain.org
            ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", .contact, 0.95)
        ]

        super.init(patterns: patterns)
    }
}
