//
//  EntityMapping.swift
//  ClinicalAnon
//
//  Purpose: Maintains consistent entity-to-replacement mappings within a session
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Redacted Person

/// Represents a redacted person with parsed name components for variant-aware replacement
struct RedactedPerson: Codable {
    let baseId: String           // "PERSON_A" (without brackets)
    let full: String             // "Sean Michael Versteegh"
    let first: String            // "Sean"
    let last: String             // "Versteegh"
    let middle: String?          // "Michael"
    let detectedTitle: String?   // "Mr", "Dr", etc.

    /// First + Middle name combination (e.g., "Sean Michael")
    var firstMiddle: String? {
        guard let mid = middle else { return nil }
        return "\(first) \(mid)"
    }

    /// First + Last name (e.g., "Sean Versteegh")
    var firstLast: String {
        "\(first) \(last)"
    }

    /// Formal address (Title + Last, e.g., "Mr Versteegh")
    var formal: String {
        let title = detectedTitle ?? "Mr"
        return "\(title) \(last)"
    }

    /// Generate placeholder for a specific variant (e.g., "[PERSON_A_FIRST]")
    func placeholder(for variant: NameVariant) -> String {
        "[\(baseId)\(variant.codeSuffix)]"
    }

    /// Get the original text for a specific variant
    func text(for variant: NameVariant) -> String {
        switch variant {
        case .full: return full
        case .first: return first
        case .last: return last
        case .middle: return middle ?? ""
        case .firstLast: return firstLast
        case .firstMiddle: return firstMiddle ?? first
        case .formal: return formal
        }
    }

    /// Detect which variant a given text represents for this person
    /// Strips titles before matching
    func detectVariant(for text: String) -> NameVariant? {
        let stripped = RedactedPerson.stripTitle(text).lowercased()
        let hasTitle = RedactedPerson.hasTitle(text)

        // Match longest first to avoid partial matches
        if stripped == full.lowercased() { return .full }
        if let fm = firstMiddle?.lowercased(), stripped == fm { return .firstMiddle }
        if stripped == firstLast.lowercased() { return .firstLast }

        // Title + Last = formal
        if hasTitle && stripped == last.lowercased() { return .formal }

        if stripped == first.lowercased() { return .first }
        if let mid = middle?.lowercased(), stripped == mid { return .middle }
        if stripped == last.lowercased() { return .last }

        return nil
    }

    // MARK: - Static Helpers

    static let titles = ["mr", "mrs", "ms", "dr", "prof", "miss", "mr.", "mrs.", "ms.", "dr.", "prof."]

    /// Check if text starts with a title
    static func hasTitle(_ text: String) -> Bool {
        let lower = text.lowercased()
        return titles.contains { lower.hasPrefix($0 + " ") }
    }

    /// Strip title from text
    static func stripTitle(_ text: String) -> String {
        let parts = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !parts.isEmpty else { return text }

        if titles.contains(parts[0].lowercased()) {
            return parts.dropFirst().joined(separator: " ")
        }
        return text
    }

    /// Extract detected title from text
    static func extractTitle(_ text: String) -> String? {
        let parts = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        let firstPart = parts[0].lowercased()
        if titles.contains(firstPart) {
            // Return with original casing but standardized (no period)
            return parts[0].replacingOccurrences(of: ".", with: "").capitalized
        }
        return nil
    }

    /// Parse a full name string into RedactedPerson
    /// - Parameters:
    ///   - fullName: The complete name (e.g., "Mr Sean Michael Versteegh")
    ///   - baseId: The base ID without brackets (e.g., "PERSON_A")
    static func parse(fullName: String, baseId: String) -> RedactedPerson {
        let detectedTitle = extractTitle(fullName)
        let stripped = stripTitle(fullName)
        let parts = stripped.components(separatedBy: " ").filter { !$0.isEmpty }

        let first = parts.first ?? stripped
        let last = parts.count >= 2 ? parts.last! : first
        let middle: String? = parts.count >= 3 ? parts[1..<parts.count-1].joined(separator: " ") : nil

        return RedactedPerson(
            baseId: baseId,
            full: stripped,
            first: first,
            last: last,
            middle: middle,
            detectedTitle: detectedTitle
        )
    }
}

// MARK: - Entity Mapping

/// Maintains consistent mappings between original entities and replacement codes
/// Ensures the same entity always gets the same replacement code within a session
@MainActor
class EntityMapping: ObservableObject {

    // MARK: - Properties

    /// Dictionary mapping original text to replacement code
    /// Key: lowercase original text, Value: replacement code
    /// Stores both normalized key and original cased text
    @Published private(set) var mappings: [String: (original: String, replacement: String)] = [:]

    /// Counter for each entity type to generate sequential codes (A, B, C, etc.)
    private var counters: [EntityType: Int] = [:]

    /// Stored RedactedPerson objects for variant-aware replacement
    /// Key: base ID (e.g., "PERSON_A"), Value: RedactedPerson
    @Published private(set) var redactedPersons: [String: RedactedPerson] = [:]

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
            return existing.replacement
        }

        // Check if this is a component of an existing mapped name
        // e.g., "Ronald" is first name of "Ronald Nath" - should share the same code
        if type.isPerson {
            if let parentCode = findParentNameCode(for: key, type: type) {
                // Store mapping with parent's code
                mappings[key] = (original: originalText, replacement: parentCode)
                return parentCode
            }
        }

        // Create new mapping
        let counter = counters[type] ?? 0
        let code = type.replacementCode(for: counter)

        // Store mapping with BOTH normalized key and original cased text
        mappings[key] = (original: originalText, replacement: code)
        counters[type] = counter + 1

        return code
    }

    /// Get or create a variant-aware replacement code for a person name
    /// - Parameters:
    ///   - originalText: The original text to map
    ///   - type: The entity type (must be a person type)
    ///   - variant: The name variant (first, last, full, etc.)
    /// - Returns: Tuple of (replacement code with variant suffix, detected variant)
    func getVariantReplacementCode(for originalText: String, type: EntityType, variant: NameVariant? = nil) -> (code: String, variant: NameVariant?) {
        guard type.isPerson else {
            return (getReplacementCode(for: originalText, type: type), nil)
        }

        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if this matches an existing RedactedPerson
        for (baseId, person) in redactedPersons {
            if let detectedVariant = person.detectVariant(for: originalText) {
                let variantCode = person.placeholder(for: detectedVariant)
                // Store mapping
                mappings[key] = (original: originalText, replacement: variantCode)
                return (variantCode, detectedVariant)
            }
        }

        // Check existing mappings
        if let existing = mappings[key] {
            // Try to detect variant from the code
            let detectedVariant = detectVariantFromCode(existing.replacement)
            return (existing.replacement, detectedVariant)
        }

        // No existing match - create new person entry if this is a full name (2+ parts)
        let stripped = RedactedPerson.stripTitle(originalText)
        let parts = stripped.components(separatedBy: " ").filter { !$0.isEmpty }

        if parts.count >= 2 {
            // This is a full name - create RedactedPerson and store
            let counter = counters[type] ?? 0
            let baseCode = type.replacementCode(for: counter)
            let baseId = String(baseCode.dropFirst().dropLast()) // Remove [ and ]

            let person = RedactedPerson.parse(fullName: originalText, baseId: baseId)
            redactedPersons[baseId] = person

            // Use explicit variant or detect it
            let finalVariant = variant ?? (parts.count > 2 ? NameVariant.full : NameVariant.firstLast)
            let variantCode = person.placeholder(for: finalVariant)

            mappings[key] = (original: originalText, replacement: variantCode)
            counters[type] = counter + 1

            #if DEBUG
            print("EntityMapping: Created RedactedPerson '\(person.full)' with baseId \(baseId)")
            #endif

            return (variantCode, finalVariant)
        } else {
            // Single name - use regular code (no variant)
            let code = getReplacementCode(for: originalText, type: type)
            return (code, nil)
        }
    }

    /// Detect variant from a replacement code (e.g., "[PERSON_A_FIRST]" -> .first)
    private func detectVariantFromCode(_ code: String) -> NameVariant? {
        for variant in NameVariant.allCases {
            if code.contains(variant.codeSuffix + "]") {
                return variant
            }
        }
        return nil
    }

    /// Get RedactedPerson for a base ID
    func getPerson(for baseId: String) -> RedactedPerson? {
        return redactedPersons[baseId]
    }

    /// Find which variant a text represents across all registered persons
    /// Returns (person, variant) if found, nil otherwise
    func findVariant(for text: String) -> (person: RedactedPerson, variant: NameVariant)? {
        for (_, person) in redactedPersons {
            if let variant = person.detectVariant(for: text) {
                return (person, variant)
            }
        }
        return nil
    }

    /// Register a full name as anchor and get its RedactedPerson
    /// Call this when you detect a full name to set up variant tracking
    func registerPersonAnchor(fullName: String, type: EntityType) -> RedactedPerson? {
        guard type.isPerson else { return nil }

        let stripped = RedactedPerson.stripTitle(fullName)
        let parts = stripped.components(separatedBy: " ").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        // Check if already registered
        for (_, person) in redactedPersons {
            if person.full.lowercased() == stripped.lowercased() {
                return person
            }
        }

        // Create new
        let counter = counters[type] ?? 0
        let baseCode = type.replacementCode(for: counter)
        let baseId = String(baseCode.dropFirst().dropLast())

        let person = RedactedPerson.parse(fullName: fullName, baseId: baseId)
        redactedPersons[baseId] = person
        counters[type] = counter + 1

        // Store mapping for the full name
        let key = fullName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let variantCode = person.placeholder(for: parts.count > 2 ? .full : .firstLast)
        mappings[key] = (original: fullName, replacement: variantCode)

        return person
    }

    /// Find if this text is related to an existing mapped name (component or extension)
    /// Returns the related name's replacement code if found
    /// Handles both directions:
    /// - "Ronald" is a component of existing "Ronald Nath" → use same code
    /// - "Ronald Nath" starts with existing "Ronald" → use same code
    private func findParentNameCode(for text: String, type: EntityType) -> String? {
        let searchText = text.lowercased()

        for (existingKey, mapping) in mappings {
            // Only check person-type mappings
            guard mapping.replacement.contains("CLIENT") ||
                  mapping.replacement.contains("PROVIDER") ||
                  mapping.replacement.contains("PERSON") else {
                continue
            }

            // Case 1: Existing key is longer - our text is a component
            // e.g., existing "ronald nath" starts with our "ronald "
            if existingKey.hasPrefix(searchText + " ") {
                #if DEBUG
                print("EntityMapping: '\(text)' is component of '\(existingKey)' → using \(mapping.replacement)")
                #endif
                return mapping.replacement
            }

            // Case 2: Our text is longer - existing key is a component
            // e.g., our "ronald nath" starts with existing "ronald "
            if searchText.hasPrefix(existingKey + " ") {
                #if DEBUG
                print("EntityMapping: '\(text)' extends '\(existingKey)' → using \(mapping.replacement)")
                #endif
                return mapping.replacement
            }
        }

        return nil
    }

    /// Check if an original text already has a mapping
    func hasMapping(for originalText: String) -> Bool {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return mappings[key] != nil
    }

    /// Get the replacement code for text if it exists
    func existingMapping(for originalText: String) -> String? {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return mappings[key]?.replacement
    }

    /// Clear all mappings (start fresh session)
    func clearAll() {
        mappings.removeAll()
        counters.removeAll()
        redactedPersons.removeAll()
    }

    /// Get all mappings as a sorted array
    /// Returns the ORIGINAL CASED text, not the normalized key
    var allMappings: [(original: String, replacement: String)] {
        return mappings.map { (original: $0.value.original, replacement: $0.value.replacement) }
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
        return mappings.values.map { $0.replacement }.filter { code in
            code.contains(type.replacementPrefix)
        }.sorted()
    }

    // MARK: - Advanced Operations

    /// Add a custom mapping (for manual overrides)
    func addMapping(originalText: String, replacementCode: String) {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        mappings[key] = (original: originalText, replacement: replacementCode)
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
            mappings[key] = (original: originalText, replacement: newReplacementCode)
        }
    }

    /// Merge one entity's mapping into another (alias → primary)
    /// The alias will adopt the primary's replacement code
    /// - Parameters:
    ///   - alias: The text to merge (will use primary's code)
    ///   - primary: The text to merge into (keeps its code)
    /// - Returns: The primary's replacement code, or nil if primary not found
    func mergeMapping(alias: String, into primary: String) -> String? {
        let aliasKey = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = primary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let primaryMapping = mappings[primaryKey] else {
            #if DEBUG
            print("EntityMapping.mergeMapping: Primary '\(primary)' not found in mappings")
            #endif
            return nil
        }

        // Point alias to primary's code
        mappings[aliasKey] = (original: alias, replacement: primaryMapping.replacement)

        #if DEBUG
        print("EntityMapping.mergeMapping: '\(alias)' merged into '\(primary)' → \(primaryMapping.replacement)")
        #endif

        return primaryMapping.replacement
    }

    /// Export mappings as JSON string
    func exportAsJSON() -> String? {
        let mappingArray = mappings.map { ["original": $0.value.original, "replacement": $0.value.replacement] }

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
            let key = original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            mappings[key] = (original: original, replacement: replacement)
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
