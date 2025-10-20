//
//  EntityMapping.swift
//  ClinicalAnon
//
//  Purpose: Maintains consistent entity-to-replacement mappings within a session
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Mapping

/// Maintains consistent mappings between original entities and replacement codes
/// Ensures the same entity always gets the same replacement code within a session
@MainActor
class EntityMapping: ObservableObject {

    // MARK: - Properties

    /// Dictionary mapping original text to replacement code
    /// Key: lowercase original text, Value: replacement code
    @Published private(set) var mappings: [String: String] = [:]

    /// Counter for each entity type to generate sequential codes (A, B, C, etc.)
    private var counters: [EntityType: Int] = [:]

    // MARK: - Public Methods

    /// Get or create a replacement code for an original text
    /// - Parameters:
    ///   - originalText: The original text to map
    ///   - type: The entity type
    /// - Returns: The replacement code (e.g., "[CLIENT_A]")
    func getReplacementCode(for originalText: String, type: EntityType) -> String {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Return existing mapping if available
        if let existing = mappings[key] {
            return existing
        }

        // Create new mapping
        let counter = counters[type] ?? 0
        let code = type.replacementCode(for: counter)

        // Store mapping
        mappings[key] = code
        counters[type] = counter + 1

        return code
    }

    /// Check if an original text already has a mapping
    func hasMapping(for originalText: String) -> Bool {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return mappings[key] != nil
    }

    /// Get the replacement code for text if it exists
    func existingMapping(for originalText: String) -> String? {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return mappings[key]
    }

    /// Clear all mappings (start fresh session)
    func clearAll() {
        mappings.removeAll()
        counters.removeAll()
    }

    /// Get all mappings as a sorted array
    var allMappings: [(original: String, replacement: String)] {
        return mappings.map { (original: $0.key, replacement: $0.value) }
            .sorted { $0.original < $1.original }
    }

    /// Total number of unique entities mapped
    var totalMappings: Int {
        return mappings.count
    }

    /// Get count for a specific entity type
    func count(for type: EntityType) -> Int {
        return counters[type] ?? 0
    }

    /// Get all replacement codes for a specific type
    func replacements(for type: EntityType) -> [String] {
        return mappings.values.filter { code in
            code.contains(type.replacementPrefix)
        }.sorted()
    }

    // MARK: - Advanced Operations

    /// Add a custom mapping (for manual overrides)
    func addMapping(originalText: String, replacementCode: String) {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        mappings[key] = replacementCode
    }

    /// Remove a specific mapping
    func removeMapping(for originalText: String) {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        mappings.removeValue(forKey: key)
    }

    /// Update an existing mapping
    func updateMapping(originalText: String, newReplacementCode: String) {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if mappings[key] != nil {
            mappings[key] = newReplacementCode
        }
    }

    /// Export mappings as JSON string
    func exportAsJSON() -> String? {
        let mappingArray = mappings.map { ["original": $0.key, "replacement": $0.value] }

        guard let data = try? JSONSerialization.data(withJSONObject: mappingArray, options: .prettyPrinted),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    /// Import mappings from JSON string
    func importFromJSON(_ json: String) throws {
        guard let data = json.data(using: .utf8),
              let mappingArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            throw AppError.malformedJSON("Could not parse mapping JSON")
        }

        clearAll()

        for mapping in mappingArray {
            guard let original = mapping["original"],
                  let replacement = mapping["replacement"] else {
                continue
            }
            mappings[original] = replacement
        }
    }

    // MARK: - Statistics

    /// Get statistics about current mappings
    var statistics: MappingStatistics {
        var typeCounts: [EntityType: Int] = [:]

        for type in EntityType.allCases {
            typeCounts[type] = count(for: type)
        }

        return MappingStatistics(
            totalMappings: totalMappings,
            typeCounts: typeCounts
        )
    }
}

// MARK: - Mapping Statistics

struct MappingStatistics {
    let totalMappings: Int
    let typeCounts: [EntityType: Int]

    var summary: String {
        var lines: [String] = ["Total entities: \(totalMappings)"]

        for type in EntityType.allCases {
            if let count = typeCounts[type], count > 0 {
                lines.append("\(type.displayName): \(count)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension EntityMapping {
    /// Sample mapping with pre-populated data
    static var sample: EntityMapping {
        let mapping = EntityMapping()
        _ = mapping.getReplacementCode(for: "Jane Smith", type: .personClient)
        _ = mapping.getReplacementCode(for: "Dr. Wilson", type: .personProvider)
        _ = mapping.getReplacementCode(for: "March 15, 2024", type: .date)
        _ = mapping.getReplacementCode(for: "Auckland", type: .location)
        return mapping
    }

    /// Empty mapping for testing
    static var empty: EntityMapping {
        return EntityMapping()
    }

    /// Mapping with many entries
    static var populated: EntityMapping {
        let mapping = EntityMapping()
        _ = mapping.getReplacementCode(for: "Client One", type: .personClient)
        _ = mapping.getReplacementCode(for: "Client Two", type: .personClient)
        _ = mapping.getReplacementCode(for: "Dr. Smith", type: .personProvider)
        _ = mapping.getReplacementCode(for: "Dr. Jones", type: .personProvider)
        _ = mapping.getReplacementCode(for: "January 1, 2024", type: .date)
        _ = mapping.getReplacementCode(for: "February 15, 2024", type: .date)
        _ = mapping.getReplacementCode(for: "Wellington", type: .location)
        _ = mapping.getReplacementCode(for: "Christchurch", type: .location)
        _ = mapping.getReplacementCode(for: "Auckland Hospital", type: .organization)
        return mapping
    }
}
#endif
