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
        // Order matters: more specific recognizers first, catch-all last
        var allRecognizers: [EntityRecognizer] = [
            AppleNERRecognizer(),          // Apple's baseline NER
            MaoriNameRecognizer(),         // NZ-specific Māori names
            RelationshipNameExtractor(),   // Extract names from "sister Margaret"
            NZPhoneRecognizer(),           // NZ phone numbers
            NZMedicalIDRecognizer(),       // NHI, ACC case numbers
            NZAddressRecognizer(),         // NZ addresses and suburbs
            DateRecognizer()               // Date patterns
        ]

        // Add catch-all number recognizer if enabled (default: ON)
        let redactAllNumbers = UserDefaults.standard.object(forKey: "redactAllNumbers") as? Bool ?? true
        if redactAllNumbers {
            allRecognizers.append(AllNumbersRecognizer())
        }

        self.recognizers = allRecognizers

        #if DEBUG
        print("🔧 Initialized SwiftNERService with \(recognizers.count) recognizers (redactAllNumbers: \(redactAllNumbers))")
        #endif
    }

    // MARK: - Entity Detection

    /// Detect entities in the given text
    /// - Parameter text: The clinical text to analyze
    /// - Returns: Array of detected entities
    func detectEntities(in text: String) async throws -> [Entity] {
        let startTime = Date()

        #if DEBUG
        print("🔍 SwiftNER: Starting entity detection...")
        print("📝 Input text length: \(text.count) chars")
        #endif

        var allEntities: [Entity] = []

        // Run all recognizers
        for recognizer in recognizers {
            let recognizerName = String(describing: type(of: recognizer))
            let entities = recognizer.recognize(in: text)

            #if DEBUG
            if !entities.isEmpty {
                print("  ✓ \(recognizerName): Found \(entities.count) entities")
            }
            #endif

            allEntities.append(contentsOf: entities)
        }

        #if DEBUG
        print("📊 Total entities found (before dedup): \(allEntities.count)")

        // DEBUG: Print all detected entities
        print("📋 All detected entities:")
        for (index, entity) in allEntities.enumerated() {
            print("  [\(index)] '\(entity.originalText)' type=\(entity.type) conf=\(entity.confidence ?? 0) pos=\(entity.positions.first ?? [0,0])")
        }
        #endif

        // Remove overlaps FIRST (keeps longer, higher-confidence entities)
        let noOverlaps = removeOverlaps(allEntities)
        #if DEBUG
        print("📊 After removing overlaps: \(noOverlaps.count)")

        // DEBUG: Print entities after overlap removal
        print("📋 After overlap removal:")
        for (index, entity) in noOverlaps.enumerated() {
            print("  [\(index)] '\(entity.originalText)' type=\(entity.type) conf=\(entity.confidence ?? 0)")
        }
        #endif

        // Then deduplicate exact matches
        let deduplicated = deduplicateEntities(noOverlaps)
        #if DEBUG
        print("📊 Unique entities after deduplication: \(deduplicated.count)")
        #endif

        // Validate all entity positions are within bounds
        let validated = validateEntityPositions(deduplicated, textLength: text.count)
        #if DEBUG
        if validated.count < deduplicated.count {
            print("⚠️ Filtered out \(deduplicated.count - validated.count) entities with invalid positions")
        }
        #endif

        // Scan for all occurrences of detected names (catches "Mark:" headings etc.)
        let withAllOccurrences = scanForAllOccurrences(validated, in: text)

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ SwiftNER: Completed in \(String(format: "%.2f", elapsed))s")
        #endif

        return withAllOccurrences
    }

    // MARK: - Position Validation

    /// Validate that all entity positions are within text bounds
    private func validateEntityPositions(_ entities: [Entity], textLength: Int) -> [Entity] {
        return entities.compactMap { entity in
            // Filter out invalid positions
            let validPositions = entity.positions.filter { position in
                guard position.count >= 2 else { return false }
                let start = position[0]
                let end = position[1]
                return start >= 0 && end <= textLength && start < end
            }

            // If no valid positions remain, skip this entity
            guard !validPositions.isEmpty else {
                #if DEBUG
                print("⚠️ Skipping entity '\(entity.originalText)' - no valid positions")
                #endif
                return nil
            }

            // If some positions were invalid, create new entity with only valid positions
            if validPositions.count < entity.positions.count {
                #if DEBUG
                print("⚠️ Entity '\(entity.originalText)' had \(entity.positions.count - validPositions.count) invalid positions")
                #endif
                return Entity(
                    id: entity.id,
                    originalText: entity.originalText,
                    replacementCode: entity.replacementCode,
                    type: entity.type,
                    positions: validPositions,
                    confidence: entity.confidence
                )
            }

            return entity
        }
    }

    // MARK: - All Occurrences Scan

    /// Scan text for all occurrences of detected name entities
    /// Ensures names detected in one context are replaced everywhere (e.g., "Mark:" headings)
    private func scanForAllOccurrences(_ entities: [Entity], in text: String) -> [Entity] {
        return entities.map { entity in
            // Only scan for person name types
            guard entity.type == .personClient ||
                  entity.type == .personProvider ||
                  entity.type == .personOther else {
                return entity
            }

            // Find all occurrences of this name in text
            var allPositions: [[Int]] = []
            var searchStart = text.startIndex

            while let range = text.range(of: entity.originalText,
                                          range: searchStart..<text.endIndex) {
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)
                allPositions.append([start, end])
                searchStart = range.upperBound
            }

            // If we found more occurrences than originally detected, update the entity
            if allPositions.count > entity.positions.count {
                #if DEBUG
                print("📍 Found \(allPositions.count) occurrences of '\(entity.originalText)' (was \(entity.positions.count))")
                #endif
                return Entity(
                    id: entity.id,
                    originalText: entity.originalText,
                    replacementCode: entity.replacementCode,
                    type: entity.type,
                    positions: allPositions,
                    confidence: entity.confidence
                )
            }

            return entity
        }
    }

    // MARK: - Overlap Removal

    /// Remove overlapping entities, keeping the best one
    /// Prioritizes: 1) Higher confidence, 2) Longer text
    private func removeOverlaps(_ entities: [Entity]) -> [Entity] {
        var sorted = entities.sorted { e1, e2 in
            guard let p1 = e1.positions.first, let p2 = e2.positions.first else {
                return false
            }
            return p1[0] < p2[0]
        }

        var result: [Entity] = []
        var i = 0

        while i < sorted.count {
            var keep = sorted[i]
            var j = i + 1

            // Check for overlaps with subsequent entities
            while j < sorted.count {
                let other = sorted[j]

                // Check if they overlap
                if entitiesOverlap(keep, other) {
                    // Keep the better entity
                    if shouldReplace(current: keep, with: other) {
                        keep = other
                    }
                    // Skip the overlapping entity
                    sorted.remove(at: j)
                } else {
                    j += 1
                }
            }

            result.append(keep)
            i += 1
        }

        return result
    }

    /// Check if two entities overlap in their text positions
    private func entitiesOverlap(_ e1: Entity, _ e2: Entity) -> Bool {
        guard let p1 = e1.positions.first, let p2 = e2.positions.first else {
            return false
        }

        let start1 = p1[0], end1 = p1[1]
        let start2 = p2[0], end2 = p2[1]

        // Check if ranges overlap
        return !(end1 <= start2 || end2 <= start1)
    }

    /// Determine if we should replace current entity with new one
    /// Prioritizes higher confidence, then longer text
    private func shouldReplace(current: Entity, with new: Entity) -> Bool {
        let currentConf = current.confidence ?? 0.0
        let newConf = new.confidence ?? 0.0

        // Prefer higher confidence
        if newConf > currentConf {
            return true
        }

        // If same confidence, prefer longer text
        if newConf == currentConf {
            return new.originalText.count > current.originalText.count
        }

        return false
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
                // ALWAYS merge positions from both entities
                let newConfidence = entity.confidence ?? 0.0
                let existingConfidence = existing.confidence ?? 0.0

                // Merge all positions
                let mergedPositions = existing.positions + entity.positions

                // Use the entity with higher confidence as the base, but keep all positions
                let merged = Entity(
                    id: existing.id,
                    originalText: existing.originalText,
                    replacementCode: existing.replacementCode,
                    type: existing.type,
                    positions: mergedPositions,
                    confidence: max(newConfidence, existingConfidence)
                )
                entityMap[key] = merged
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
            .contact: 3,
            .numericAll: 1  // Lowest priority - specific detectors take precedence
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
