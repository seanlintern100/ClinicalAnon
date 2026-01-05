//
//  AnonymizationResult.swift
//  ClinicalAnon
//
//  Purpose: Complete result structure for anonymization operations
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Anonymization Result

/// Complete result of an anonymization operation
struct AnonymizationResult: Identifiable, Codable {

    // MARK: - Properties

    /// Unique identifier for this result
    let id: UUID

    /// The original clinical text before anonymization
    let originalText: String

    /// The anonymized text with replacement codes
    let anonymizedText: String

    /// All entities detected and replaced
    var entities: [Entity]

    /// Timestamp when this anonymization was performed
    let timestamp: Date

    /// Optional metadata about the operation
    let metadata: AnonymizationMetadata?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        originalText: String,
        anonymizedText: String,
        entities: [Entity],
        timestamp: Date = Date(),
        metadata: AnonymizationMetadata? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.anonymizedText = anonymizedText
        self.entities = entities
        self.timestamp = timestamp
        self.metadata = metadata
    }

    // MARK: - Computed Properties

    /// Total number of entities detected
    var entityCount: Int {
        return entities.count
    }

    /// Total number of replacements made across all entities
    var replacementCount: Int {
        return entities.reduce(0) { $0 + $1.occurrenceCount }
    }

    /// Entities grouped by type
    var entitiesByType: [EntityType: [Entity]] {
        var grouped: [EntityType: [Entity]] = [:]

        for entity in entities {
            if grouped[entity.type] != nil {
                grouped[entity.type]?.append(entity)
            } else {
                grouped[entity.type] = [entity]
            }
        }

        return grouped
    }

    /// Sorted entities (by first occurrence position)
    var sortedEntities: [Entity] {
        return entities.sorted()
    }

    /// Character count of original text
    var originalCharacterCount: Int {
        return originalText.count
    }

    /// Character count of anonymized text
    var anonymizedCharacterCount: Int {
        return anonymizedText.count
    }

    /// Check if any entities were detected
    var hasEntities: Bool {
        return !entities.isEmpty
    }

    /// Summary text for display
    var summary: String {
        return "Found \(entityCount) unique \(entityCount == 1 ? "entity" : "entities") with \(replacementCount) total \(replacementCount == 1 ? "replacement" : "replacements")"
    }

    // MARK: - Helper Methods

    /// Get all entities of a specific type
    func entities(ofType type: EntityType) -> [Entity] {
        return entities.filter { $0.type == type }
    }

    /// Find entity at a specific character position in original text
    func entity(at position: Int) -> Entity? {
        return entities.first { $0.contains(position: position) }
    }

    /// Check if position is within an entity
    func isEntityPosition(_ position: Int) -> Bool {
        return entity(at: position) != nil
    }

    /// Get statistics about entity types
    var typeStatistics: [EntityType: Int] {
        var stats: [EntityType: Int] = [:]

        for entity in entities {
            stats[entity.type, default: 0] += 1
        }

        return stats
    }

    /// Export result as formatted text
    func exportAsText() -> String {
        var output: [String] = []

        output.append("=== ANONYMIZATION RESULT ===")
        output.append("Date: \(timestamp.formatted())")
        output.append("")
        output.append("Summary: \(summary)")
        output.append("")
        output.append("--- ANONYMIZED TEXT ---")
        output.append(anonymizedText)
        output.append("")
        output.append("--- DETECTED ENTITIES ---")

        for (type, typeEntities) in entitiesByType.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            output.append("")
            output.append("\(type.displayName):")
            for entity in typeEntities.sorted() {
                output.append("  • \(entity.originalText) → \(entity.replacementCode)")
            }
        }

        return output.joined(separator: "\n")
    }
}

// MARK: - Anonymization Metadata

/// Optional metadata about the anonymization operation
struct AnonymizationMetadata: Codable {

    /// Model used for anonymization (e.g., "mistral:latest")
    let modelUsed: String?

    /// Processing time in seconds
    let processingTime: TimeInterval?

    /// Average confidence score across all entities
    let averageConfidence: Double?

    /// Notes or additional context
    let notes: String?

    /// Version of the app that created this result
    let appVersion: String?

    init(
        modelUsed: String? = nil,
        processingTime: TimeInterval? = nil,
        averageConfidence: Double? = nil,
        notes: String? = nil,
        appVersion: String? = nil
    ) {
        self.modelUsed = modelUsed
        self.processingTime = processingTime
        self.averageConfidence = averageConfidence
        self.notes = notes
        self.appVersion = appVersion
    }

    /// Formatted processing time
    var formattedProcessingTime: String? {
        guard let time = processingTime else { return nil }
        return String(format: "%.2f seconds", time)
    }

    /// Formatted confidence percentage
    var formattedConfidence: String? {
        guard let confidence = averageConfidence else { return nil }
        return String(format: "%.1f%%", confidence * 100)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension AnonymizationResult {
    /// Sample result with realistic data
    static var sample: AnonymizationResult {
        let originalText = """
        Jane Smith attended her session on March 15, 2024. \
        Dr. Wilson conducted the assessment at Auckland Clinic. \
        Jane discussed her progress with managing anxiety symptoms.
        """

        let anonymizedText = """
        [CLIENT_A] attended her session on [DATE_A]. \
        [PROVIDER_A] conducted the assessment at [LOCATION_A]. \
        [CLIENT_A] discussed her progress with managing anxiety symptoms.
        """

        return AnonymizationResult(
            originalText: originalText,
            anonymizedText: anonymizedText,
            entities: Entity.samples,
            metadata: AnonymizationMetadata(
                modelUsed: "mistral:latest",
                processingTime: 1.23,
                averageConfidence: 0.94,
                appVersion: "1.0.0"
            )
        )
    }

    /// Empty result
    static var empty: AnonymizationResult {
        return AnonymizationResult(
            originalText: "",
            anonymizedText: "",
            entities: []
        )
    }

    /// Result with no entities detected
    static var noEntities: AnonymizationResult {
        let text = "The client reported improvement in symptoms over the past week."

        return AnonymizationResult(
            originalText: text,
            anonymizedText: text,
            entities: []
        )
    }

    /// Result with many entities
    static var complex: AnonymizationResult {
        let originalText = """
        Session with Sarah Johnson on January 15, 2024 at Wellington Office.
        Dr. Martinez and Dr. Lee both attended. Sarah's mother Mary Johnson
        was also present. Contact: sarah@email.com, phone 021-555-0123.
        Previous session was December 20, 2023 at Auckland branch.
        """

        let anonymizedText = """
        Session with [CLIENT_A] on [DATE_A] at [LOCATION_A].
        [PROVIDER_A] and [PROVIDER_B] both attended. [CLIENT_A]'s mother [PERSON_A]
        was also present. Contact: [CONTACT_A], phone [CONTACT_B].
        Previous session was [DATE_B] at [LOCATION_B].
        """

        let entities = [
            Entity(originalText: "Sarah Johnson", replacementCode: "[CLIENT_A]", type: .personClient, positions: [[13, 26], [88, 101]], confidence: 0.98),
            Entity(originalText: "January 15, 2024", replacementCode: "[DATE_A]", type: .date, positions: [[30, 46]], confidence: 1.0),
            Entity(originalText: "Wellington Office", replacementCode: "[LOCATION_A]", type: .location, positions: [[50, 67]], confidence: 0.92),
            Entity(originalText: "Dr. Martinez", replacementCode: "[PROVIDER_A]", type: .personProvider, positions: [[69, 81]], confidence: 0.99),
            Entity(originalText: "Dr. Lee", replacementCode: "[PROVIDER_B]", type: .personProvider, positions: [[86, 93]], confidence: 0.99),
            Entity(originalText: "Mary Johnson", replacementCode: "[PERSON_A]", type: .personOther, positions: [[125, 137]], confidence: 0.95),
            Entity(originalText: "sarah@email.com", replacementCode: "[CONTACT_A]", type: .contact, positions: [[160, 175]], confidence: 1.0),
            Entity(originalText: "021-555-0123", replacementCode: "[CONTACT_B]", type: .contact, positions: [[183, 195]], confidence: 1.0),
            Entity(originalText: "December 20, 2023", replacementCode: "[DATE_B]", type: .date, positions: [[217, 234]], confidence: 1.0),
            Entity(originalText: "Auckland branch", replacementCode: "[LOCATION_B]", type: .location, positions: [[238, 253]], confidence: 0.90)
        ]

        return AnonymizationResult(
            originalText: originalText,
            anonymizedText: anonymizedText,
            entities: entities,
            metadata: AnonymizationMetadata(
                modelUsed: "mistral:latest",
                processingTime: 2.45,
                averageConfidence: 0.96,
                appVersion: "1.0.0"
            )
        )
    }
}

extension AnonymizationMetadata {
    static var sample: AnonymizationMetadata {
        return AnonymizationMetadata(
            modelUsed: "mistral:latest",
            processingTime: 1.5,
            averageConfidence: 0.95,
            notes: "Successfully processed",
            appVersion: "1.0.0"
        )
    }
}
#endif
