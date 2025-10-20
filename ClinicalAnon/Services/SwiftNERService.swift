//
//  SwiftNERService.swift
//  ClinicalAnon
//
//  Purpose: Swift-native entity recognition using Apple NER + custom NZ recognizers
//  Organization: 3 Big Things
//

import Foundation
import NaturalLanguage

// MARK: - Swift NER Service

/// Swift-native entity detection service
/// Combines Apple's NaturalLanguage framework with custom NZ-specific recognizers
class SwiftNERService {

    // MARK: - Properties

    private let recognizers: [EntityRecognizer]

    // MARK: - Initialization

    init() {
        // Initialize all recognizers
        // Order matters: more specific recognizers first
        self.recognizers = [
            AppleNERRecognizer(),          // Apple's baseline NER
            MaoriNameRecognizer(),         // NZ-specific Māori names
            RelationshipNameExtractor(),   // Extract names from "sister Margaret"
            NZPhoneRecognizer(),           // NZ phone numbers
            NZMedicalIDRecognizer(),       // NHI, ACC case numbers
            NZAddressRecognizer(),         // NZ addresses and suburbs
            DateRecognizer()               // Date patterns
        ]

        print("🔧 Initialized SwiftNERService with \(recognizers.count) recognizers")
    }

    // MARK: - Entity Detection

    /// Detect entities in the given text
    /// - Parameter text: The clinical text to analyze
    /// - Returns: Array of detected entities
    func detectEntities(in text: String) async throws -> [Entity] {
        let startTime = Date()

        print("🔍 SwiftNER: Starting entity detection...")
        print("📝 Input text length: \(text.count) chars")

        var allEntities: [Entity] = []

        // Run all recognizers
        for recognizer in recognizers {
            let recognizerName = String(describing: type(of: recognizer))
            let entities = recognizer.recognize(in: text)

            if !entities.isEmpty {
                print("  ✓ \(recognizerName): Found \(entities.count) entities")
            }

            allEntities.append(contentsOf: entities)
        }

        print("📊 Total entities found (before dedup): \(allEntities.count)")

        // Deduplicate overlapping entities
        let deduplicated = deduplicateEntities(allEntities)

        print("📊 Unique entities after deduplication: \(deduplicated.count)")

        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ SwiftNER: Completed in \(String(format: "%.2f", elapsed))s")

        return deduplicated
    }

    // MARK: - Deduplication

    /// Deduplicate entities that refer to the same text
    /// Keeps the entity with highest confidence for each unique text
    private func deduplicateEntities(_ entities: [Entity]) -> [Entity] {
        // Group by normalized text
        var entityMap: [String: Entity] = [:]

        for entity in entities {
            let key = entity.originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty or very short entities
            guard key.count > 1 else { continue }

            if let existing = entityMap[key] {
                // Keep entity with higher confidence
                let newConfidence = entity.confidence ?? 0.0
                let existingConfidence = existing.confidence ?? 0.0

                if newConfidence > existingConfidence {
                    // Replace with higher confidence entity
                    entityMap[key] = entity
                } else if newConfidence == existingConfidence {
                    // Same confidence - merge positions by creating new entity
                    let mergedPositions = existing.positions + entity.positions
                    let merged = Entity(
                        id: existing.id,
                        originalText: existing.originalText,
                        replacementCode: existing.replacementCode,
                        type: existing.type,
                        positions: mergedPositions,
                        confidence: existing.confidence
                    )
                    entityMap[key] = merged
                }
            } else {
                // First time seeing this entity
                entityMap[key] = entity
            }
        }

        // Convert back to array and sort by first position
        let deduplicated = Array(entityMap.values).sorted { e1, e2 in
            guard let p1 = e1.positions.first, let p2 = e2.positions.first else {
                return false
            }
            return p1[0] < p2[0]
        }

        return deduplicated
    }

    /// Resolve conflicts when same text is detected with different types
    /// Example: "Margaret" detected as both client_name and other_name
    private func resolveTypeConflicts(_ entities: [Entity]) -> [Entity] {
        // Type priority: client > provider > other
        // If same text has multiple types, keep highest priority

        let typePriority: [EntityType: Int] = [
            .personClient: 3,
            .personProvider: 2,
            .personOther: 1,
            .date: 2,
            .location: 2,
            .organization: 2,
            .identifier: 2,
            .contact: 3
        ]

        var entityMap: [String: Entity] = [:]

        for entity in entities {
            let key = entity.originalText.lowercased()

            if let existing = entityMap[key] {
                let newPriority = typePriority[entity.type] ?? 0
                let existingPriority = typePriority[existing.type] ?? 0

                if newPriority > existingPriority {
                    entityMap[key] = entity
                } else if newPriority == existingPriority {
                    // Same priority - use confidence
                    if (entity.confidence ?? 0) > (existing.confidence ?? 0) {
                        entityMap[key] = entity
                    }
                }
            } else {
                entityMap[key] = entity
            }
        }

        return Array(entityMap.values)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension SwiftNERService {
    /// Service for previews
    static var preview: SwiftNERService {
        return SwiftNERService()
    }

    /// Test detection with sample text
    func testDetection() async throws -> [Entity] {
        let sampleText = """
        Wiremu attended his session with sister Margaret and friend Aroha.
        Contact: 021-555-1234
        NHI: ABC1234
        Address: 45 High Street, Otahuhu
        Date: 15/03/2024
        """

        return try await detectEntities(in: sampleText)
    }
}
#endif
