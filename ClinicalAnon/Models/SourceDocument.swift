//
//  SourceDocument.swift
//  Redactor
//
//  Purpose: Represents a source document in multi-document workflow
//

import Foundation

/// Represents a single source document that has been redacted
/// Used when multiple documents need to be referenced for AI output generation
struct SourceDocument: Identifiable, Codable {
    let id: UUID
    let documentNumber: Int           // Auto-generated: 1, 2, 3...
    var name: String                  // "Document 1", "Document 2"
    var description: String           // Optional user description
    let originalText: String          // Original input text
    let redactedText: String          // Redacted version with placeholders
    let entities: [Entity]            // Entities detected in this document
    let timestamp: Date               // When document was added

    /// Display name combining name and description
    var displayName: String {
        description.isEmpty ? name : "\(name): \(description)"
    }

    /// Word count of original text
    var wordCount: Int {
        originalText.split(separator: " ").count
    }

    init(
        id: UUID = UUID(),
        documentNumber: Int,
        name: String,
        description: String = "",
        originalText: String,
        redactedText: String,
        entities: [Entity],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.documentNumber = documentNumber
        self.name = name
        self.description = description
        self.originalText = originalText
        self.redactedText = redactedText
        self.entities = entities
        self.timestamp = timestamp
    }
}
