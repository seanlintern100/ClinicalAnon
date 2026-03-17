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
    /// For single-name people (blank/same surname), returns just the first name
    var firstLast: String {
        if last.isEmpty || last == first {
            return first
        }
        return "\(first) \(last)"
    }

    /// Formal address (Title + Last, e.g., "Mr Versteegh")
    /// Returns empty if no last name (single-name person can't have formal address)
    var formal: String {
        guard !last.isEmpty else { return "" }
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
    /// Strips titles before matching, supports prefix matching for nicknames
    func detectVariant(for text: String) -> NameVariant? {
        let stripped = RedactedPerson.stripTitle(text).lowercased()
        let hasTitle = RedactedPerson.hasTitle(text)

        // Exact matches first (longest to shortest)
        if stripped == full.lowercased() { return .full }
        if let fm = firstMiddle?.lowercased(), stripped == fm { return .firstMiddle }
        if stripped == firstLast.lowercased() { return .firstLast }

        // Title + Last = formal
        if hasTitle && stripped == last.lowercased() { return .formal }

        if stripped == first.lowercased() { return .first }
        if let mid = middle?.lowercased(), stripped == mid { return .middle }
        if stripped == last.lowercased() { return .last }

        // Prefix matching for nicknames (e.g., "Ron" ↔ "Ronald")
        let firstLower = first.lowercased()
        if stripped.count >= 3 {  // Minimum 3 chars to avoid false positives
            // Check if alias is prefix of first name: "Ron" is prefix of "Ronald"
            if firstLower.hasPrefix(stripped) { return .first }
            // Check if first name is prefix of alias: "Ronald" is prefix of "Ronaldo"
            if stripped.hasPrefix(firstLower) { return .first }
        }

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
        // e.g., "John" is first name of "John Smith" - should share the same code
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
                // Store mapping with PRIMARY's text (not detected alias) for correct restoration
                let primaryText = person.text(for: detectedVariant)
                mappings[key] = (original: primaryText, replacement: variantCode)
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
    /// Returns the variant-aware replacement code if found
    /// Handles both directions:
    /// - "John" is a component of existing "John Smith" → use [PERSON_A_FIRST]
    /// - "John Smith" starts with existing "John" → use same code
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
            // e.g., existing "john smith" starts with our "john "
            if existingKey.hasPrefix(searchText + " ") {
                // Find the RedactedPerson and generate correct variant code
                if let baseId = extractBaseId(from: mapping.replacement),
                   let person = redactedPersons[baseId],
                   let variant = person.detectVariant(for: text) {
                    let variantCode = person.placeholder(for: variant)
                    #if DEBUG
                    print("EntityMapping: '\(text)' is component of '\(existingKey)' → using \(variantCode) (variant: \(variant))")
                    #endif
                    return variantCode
                }
                // Fallback to parent's code if no variant detected
                #if DEBUG
                print("EntityMapping: '\(text)' is component of '\(existingKey)' → using \(mapping.replacement) (no variant)")
                #endif
                return mapping.replacement
            }

            // Case 2: Our text is longer - existing key is a component
            // e.g., our "john smith" starts with existing "john "
            if searchText.hasPrefix(existingKey + " ") {
                #if DEBUG
                print("EntityMapping: '\(text)' extends '\(existingKey)' → using \(mapping.replacement)")
                #endif
                return mapping.replacement
            }
        }

        return nil
    }

    /// Extract base ID from a replacement code (e.g., "[PERSON_A_FIRST_LAST]" → "PERSON_A")
    private func extractBaseId(from code: String) -> String? {
        // Remove brackets: "[PERSON_A_FIRST_LAST]" → "PERSON_A_FIRST_LAST"
        let stripped = code.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        // Check for variant suffixes and remove them
        for variant in NameVariant.allCases {
            if stripped.hasSuffix(variant.codeSuffix) {
                let baseId = String(stripped.dropLast(variant.codeSuffix.count))
                return baseId
            }
        }

        // No variant suffix - the code itself is the base ID
        return stripped
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

    /// Get all mappings as a sorted array for restoration
    /// - Person codes: Generated from RedactedPerson (source of truth, ignores mappings.original)
    /// - Non-person codes: Uses stored mappings.original
    /// Guarantees all variant codes have a restoration value
    var allMappings: [(original: String, replacement: String)] {
        var byCode: [String: (original: String, replacement: String)] = [:]

        // Step 1: Collect all unique baseIds that have a RedactedPerson
        var personBaseIds = Set<String>()
        for (_, value) in mappings {
            if let baseId = extractBaseId(from: value.replacement),
               redactedPersons[baseId] != nil {
                personBaseIds.insert(baseId)
            }
        }

        // Step 2: Generate ALL variants for each RedactedPerson
        // This is the source of truth - ignores what's stored in mappings.original
        // Every variant code gets a mapping (fallback to first/full name for empty variants)
        // so AI-used codes like [PERSON_A_LAST] always restore even for single-name people
        for baseId in personBaseIds {
            guard let person = redactedPersons[baseId] else { continue }

            // Best available fallback: first name, then full name
            let fallback = person.first.isEmpty ? person.full : person.first

            // Base code → first name
            let baseCode = "[\(baseId)]"
            byCode[baseCode] = (original: fallback, replacement: baseCode)

            // All variant codes from person.text(for: variant)
            // Empty variants fall back to first/full name so every code restores
            for variant in NameVariant.allCases {
                let variantCode = person.placeholder(for: variant)
                let text = person.text(for: variant)
                let resolvedText = text.isEmpty ? fallback : text
                if !resolvedText.isEmpty {
                    byCode[variantCode] = (original: resolvedText, replacement: variantCode)
                }
            }
        }

        // Step 3: Add non-person mappings (dates, locations, orgs, etc.) as-is
        // Also add person codes that don't have a RedactedPerson (single names)
        // Process non-empty originals first to prevent empty AI-generated entries from shadowing
        let sortedMappings = mappings.values.sorted { a, b in
            if a.original.isEmpty != b.original.isEmpty {
                return !a.original.isEmpty // non-empty first
            }
            return a.replacement < b.replacement
        }
        for value in sortedMappings {
            let code = value.replacement
            if byCode[code] == nil {
                // Skip entries with empty original if a base code exists that will generate variants
                // This prevents AI-generated empty entries from shadowing real mappings
                if value.original.isEmpty {
                    if let baseId = extractBaseId(from: code) {
                        let baseCode = "[\(baseId)]"
                        if baseCode != code && byCode[baseCode] != nil {
                            continue
                        }
                    }
                }

                // For non-person codes, or person codes without RedactedPerson
                byCode[code] = (original: value.original, replacement: code)

                // For single-name person codes without RedactedPerson, add variant aliases
                if code.contains("PERSON") || code.contains("CLIENT") || code.contains("PROVIDER") || code.contains("CLINICIAN") {
                    let hasVariant = NameVariant.allCases.contains { code.contains($0.codeSuffix + "]") }
                    if !hasVariant {
                        let baseId = String(code.dropFirst().dropLast())
                        for variant in NameVariant.allCases {
                            let variantCode = "[\(baseId)\(variant.codeSuffix)]"
                            if byCode[variantCode] == nil {
                                byCode[variantCode] = (original: value.original, replacement: variantCode)
                            }
                        }
                    }
                }
            }
        }

        // Step 4: Fix AI prefix swaps
        // The AI sometimes changes person type prefixes in its output
        // (e.g., redacted text has [PERSON_A] but AI writes [CLIENT_A])
        // When a person code has empty original, check if the same letter
        // exists under a different prefix with a non-empty original
        let personPrefixes = ["CLIENT", "PERSON", "PROVIDER", "CLINICIAN"]
        var prefixFixes: [(code: String, original: String)] = []
        for (code, entry) in byCode where entry.original.isEmpty {
            let stripped = code.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let parts = stripped.split(separator: "_", maxSplits: 1)
            guard parts.count == 2, personPrefixes.contains(String(parts[0])) else { continue }
            let letterAndSuffix = String(parts[1]) // e.g., "A" or "A_FIRST"

            for altPrefix in personPrefixes where altPrefix != String(parts[0]) {
                let altCode = "[\(altPrefix)_\(letterAndSuffix)]"
                if let altEntry = byCode[altCode], !altEntry.original.isEmpty {
                    prefixFixes.append((code: code, original: altEntry.original))
                    break
                }
            }
        }
        for fix in prefixFixes {
            byCode[fix.code] = (original: fix.original, replacement: fix.code)
        }

        return Array(byCode.values).sorted { $0.original < $1.original }
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

    /// Sync a mapping with a source document entity
    /// Handles stale codes from reclassification: if entity was reclassified (e.g., PERSON_A → CLIENT_A)
    /// but the mapping was never updated, this detects the mismatch and fixes it
    func syncMapping(originalText: String, replacementCode: String) {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = mappings[key] {
            if existing.replacement != replacementCode {
                // Code changed — likely reclassification that wasn't synced
                // Use updateBaseId to also migrate RedactedPerson if needed
                if let oldBaseId = extractBaseId(from: existing.replacement),
                   let newBaseId = extractBaseId(from: replacementCode),
                   oldBaseId != newBaseId {
                    updateBaseId(from: oldBaseId, to: newBaseId)
                } else {
                    // Same base ID but different variant — just update the code
                    mappings[key] = (original: originalText, replacement: replacementCode)
                }

                #if DEBUG
                print("EntityMapping.syncMapping: '\(originalText)' code updated \(existing.replacement) → \(replacementCode)")
                #endif
            }
            // Same code — no action needed
        } else {
            // New mapping
            mappings[key] = (original: originalText, replacement: replacementCode)
        }

        // Ensure a RedactedPerson exists for person codes so variant restoration works.
        // Without this, reclassified entities (e.g., PERSON→CLIENT) may lack a RedactedPerson,
        // causing AI-generated variant codes like [CLIENT_J_FIRST] to be unmapped at restore time.
        let isPersonCode = replacementCode.contains("PERSON") ||
                           replacementCode.contains("CLIENT") ||
                           replacementCode.contains("PROVIDER")
        if isPersonCode, let baseId = extractBaseId(from: replacementCode) {
            if redactedPersons[baseId] == nil {
                let person = RedactedPerson.parse(fullName: originalText, baseId: baseId)
                redactedPersons[baseId] = person
            }
        }
    }

    /// Check if a mapping exists for a given original text (case-insensitive)
    func hasMapping(forOriginalText originalText: String) -> Bool {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return mappings[key] != nil
    }

    /// Check if a mapping exists for a specific replacement code
    func hasMappingForCode(_ code: String) -> Bool {
        return mappings.values.contains { $0.replacement == code }
    }

    /// Register a placeholder generated by AI that wasn't in original text
    /// These appear in Restore phase with empty original text for user to fill in
    func addAIGeneratedPlaceholder(_ placeholder: String) {
        // Only add if not already mapped
        guard !hasMappingForCode(placeholder) else { return }

        // For person variant codes like [CLIENT_A_FIRST], check if the base code
        // [CLIENT_A] already exists. If so, allMappings will generate this variant
        // automatically with the correct original text — adding an empty mapping here
        // would shadow that generated variant (non-deterministic dictionary iteration bug)
        if let baseId = extractBaseId(from: placeholder) {
            let baseCode = "[\(baseId)]"
            if baseCode != placeholder && hasMappingForCode(baseCode) {
                return
            }
        }

        // Truly AI-generated placeholder with no base mapping
        let key = placeholder.lowercased()
        mappings[key] = (original: "", replacement: placeholder)
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

    /// Update all mappings and RedactedPersons when an entity's base ID changes (reclassification)
    /// For example, when PERSON_A is reclassified to CLIENT_A:
    /// - Moves RedactedPerson from "PERSON_A" to "CLIENT_A" (with updated baseId)
    /// - Updates all mapping entries whose replacement code starts with [PERSON_A to [CLIENT_A
    func updateBaseId(from oldBaseId: String, to newBaseId: String) {
        guard oldBaseId != newBaseId else { return }

        // Update RedactedPerson if exists
        if let oldPerson = redactedPersons[oldBaseId] {
            let newPerson = RedactedPerson(
                baseId: newBaseId,
                full: oldPerson.full,
                first: oldPerson.first,
                last: oldPerson.last,
                middle: oldPerson.middle,
                detectedTitle: oldPerson.detectedTitle
            )
            redactedPersons.removeValue(forKey: oldBaseId)
            redactedPersons[newBaseId] = newPerson
        }

        // Update all mappings whose replacement code uses the old base ID
        // e.g., [PERSON_A] → [CLIENT_A], [PERSON_A_FIRST] → [CLIENT_A_FIRST]
        for (key, value) in mappings {
            let code = value.replacement
            let oldBase = "[\(oldBaseId)]"
            let oldBasePrefix = "[\(oldBaseId)_"

            if code == oldBase {
                // Exact base code match: [PERSON_A] → [CLIENT_A]
                let newCode = "[\(newBaseId)]"
                mappings[key] = (original: value.original, replacement: newCode)
            } else if code.hasPrefix(oldBasePrefix) {
                // Variant code match: [PERSON_A_FIRST] → [CLIENT_A_FIRST]
                let suffix = String(code.dropFirst(oldBasePrefix.count - 1)) // keep the underscore and rest
                let newCode = "[\(newBaseId)\(suffix)"
                mappings[key] = (original: value.original, replacement: newCode)
            }
        }

        #if DEBUG
        print("EntityMapping.updateBaseId: \(oldBaseId) → \(newBaseId)")
        #endif
    }

    /// Reclassify an entity to a new type, generating a new replacement code
    /// - Parameters:
    ///   - originalText: The text being reclassified
    ///   - newType: The new entity type
    /// - Returns: The new replacement code for the new type
    func reclassifyMapping(originalText: String, to newType: EntityType) -> String {
        let key = originalText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove old mapping if exists
        mappings.removeValue(forKey: key)

        // Generate new code for the new type
        let counter = counters[newType] ?? 0
        let newCode = newType.replacementCode(for: counter)

        // Store new mapping
        mappings[key] = (original: originalText, replacement: newCode)
        counters[newType] = counter + 1

        #if DEBUG
        print("EntityMapping.reclassifyMapping: '\(originalText)' → \(newCode) (type: \(newType.displayName))")
        #endif

        return newCode
    }

    /// Migrate a RedactedPerson entry from one baseId to another (e.g., PERSON_A → CLIENT_A on reclassify).
    /// Updates the person record and refreshes all variant mappings.
    func migratePersonBaseId(from oldBaseId: String, to newBaseId: String) {
        guard oldBaseId != newBaseId,
              let person = redactedPersons[oldBaseId] else { return }

        let migrated = RedactedPerson(
            baseId: newBaseId,
            full: person.full,
            first: person.first,
            last: person.last,
            middle: person.middle,
            detectedTitle: person.detectedTitle
        )
        redactedPersons[newBaseId] = migrated
        redactedPersons.removeValue(forKey: oldBaseId)

        updateMappingsForPerson(migrated)

        #if DEBUG
        print("EntityMapping.migratePersonBaseId: \(oldBaseId) → \(newBaseId)")
        #endif
    }

    /// Merge one entity's mapping into another (alias → primary)
    /// Creates a RedactedPerson anchor and assigns variant-specific codes
    /// - Parameters:
    ///   - alias: The text to merge (will get variant-specific code)
    ///   - primary: The text to merge into (the full name anchor)
    /// - Returns: The alias's new replacement code, or nil if primary not found
    func mergeMapping(alias: String, into primary: String) -> String? {
        let aliasKey = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = primary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let primaryMapping = mappings[primaryKey] else {
            #if DEBUG
            print("EntityMapping.mergeMapping: Primary '\(primary)' not found in mappings")
            #endif
            return nil
        }

        // Extract base ID from primary's code
        guard let baseId = extractBaseId(from: primaryMapping.replacement) else {
            // Fallback to old behavior if no base ID extractable
            mappings[aliasKey] = (original: alias, replacement: primaryMapping.replacement)
            #if DEBUG
            print("EntityMapping.mergeMapping: No baseId, fallback → '\(alias)' → \(primaryMapping.replacement)")
            #endif
            return primaryMapping.replacement
        }

        // Create RedactedPerson if doesn't exist
        if redactedPersons[baseId] == nil {
            let person = RedactedPerson.parse(fullName: primary, baseId: baseId)
            redactedPersons[baseId] = person

            // Update primary mapping to use proper variant code
            let primaryVariant: NameVariant = person.middle != nil ? .full : .firstLast
            let primaryCode = person.placeholder(for: primaryVariant)
            mappings[primaryKey] = (original: primary, replacement: primaryCode)

            #if DEBUG
            print("EntityMapping.mergeMapping: Created RedactedPerson '\(person.full)' baseId=\(baseId)")
            print("  Primary updated: '\(primary)' → \(primaryCode)")
            #endif
        }

        // Detect alias variant and assign correct code
        guard let person = redactedPersons[baseId] else {
            // No person registered - use primary's code as fallback
            mappings[aliasKey] = (original: alias, replacement: primaryMapping.replacement)
            #if DEBUG
            print("EntityMapping.mergeMapping: No person for baseId '\(baseId)', fallback → '\(alias)' → \(primaryMapping.replacement)")
            #endif
            return primaryMapping.replacement
        }

        // Try to detect variant using existing logic
        if let variant = person.detectVariant(for: alias) {
            let variantCode = person.placeholder(for: variant)
            let primaryText = person.text(for: variant)  // Use primary's text, not alias
            mappings[aliasKey] = (original: primaryText, replacement: variantCode)

            #if DEBUG
            print("EntityMapping.mergeMapping: '\(alias)' → \(variantCode) (variant: \(variant), restores to: '\(primaryText)')")
            #endif

            return variantCode
        } else {
            // Variant not detected - infer from name component matching
            let inferredVariant = inferVariantFromNameMatch(alias: alias, person: person)
            let variantCode = person.placeholder(for: inferredVariant)
            let primaryText = person.text(for: inferredVariant)  // Use primary's text, not alias
            mappings[aliasKey] = (original: primaryText, replacement: variantCode)

            #if DEBUG
            print("EntityMapping.mergeMapping: '\(alias)' → \(variantCode) (inferred: \(inferredVariant), restores to: '\(primaryText)')")
            #endif

            return variantCode
        }
    }

    /// Infer variant by checking if alias matches first, last, or other name component
    /// Used as fallback when detectVariant() fails
    private func inferVariantFromNameMatch(alias: String, person: RedactedPerson) -> NameVariant {
        let aliasLower = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check exact matches with name components
        if aliasLower == person.first.lowercased() {
            return .first
        }
        if aliasLower == person.last.lowercased() {
            return .last
        }
        if let middle = person.middle?.lowercased(), aliasLower == middle {
            return .middle
        }

        // Check if it contains first + last (no middle)
        let firstLast = "\(person.first) \(person.last)".lowercased()
        if aliasLower == firstLast {
            return .firstLast
        }

        // Default to first name if single word, otherwise firstLast
        return alias.contains(" ") ? .firstLast : .first
    }

    /// Result of attempting to merge with variant detection
    enum MergeResult {
        case success(code: String, variant: NameVariant)
        case variantNotDetected(baseId: String, primaryCode: String)
        case primaryNotFound
        case noBaseId
    }

    /// Try to merge mapping with variant detection, returning result for UI handling
    /// Unlike mergeMapping(), this does NOT fallback - lets caller decide what to do
    func tryMergeMapping(alias: String, into primary: String) -> MergeResult {
        let aliasKey = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = primary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let primaryMapping = mappings[primaryKey] else {
            return .primaryNotFound
        }

        guard let baseId = extractBaseId(from: primaryMapping.replacement) else {
            return .noBaseId
        }

        // Create RedactedPerson if doesn't exist
        if redactedPersons[baseId] == nil {
            let person = RedactedPerson.parse(fullName: primary, baseId: baseId)
            redactedPersons[baseId] = person

            let primaryVariant: NameVariant = person.middle != nil ? .full : .firstLast
            let primaryCode = person.placeholder(for: primaryVariant)
            mappings[primaryKey] = (original: primary, replacement: primaryCode)
        }

        // Try to detect variant
        if let person = redactedPersons[baseId],
           let variant = person.detectVariant(for: alias) {
            let variantCode = person.placeholder(for: variant)
            let primaryText = person.text(for: variant)  // Use primary's text, not alias
            mappings[aliasKey] = (original: primaryText, replacement: variantCode)
            return .success(code: variantCode, variant: variant)
        } else {
            // Variant not detected - return info for UI prompt
            let currentPrimaryCode = mappings[primaryKey]?.replacement ?? primaryMapping.replacement
            return .variantNotDetected(baseId: baseId, primaryCode: currentPrimaryCode)
        }
    }

    /// Complete a merge with a user-specified variant
    /// Called after user selects variant from prompt
    func completeMergeWithVariant(alias: String, into primary: String, variant: NameVariant) -> String? {
        let aliasKey = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryKey = primary.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let primaryMapping = mappings[primaryKey],
              let baseId = extractBaseId(from: primaryMapping.replacement),
              let person = redactedPersons[baseId] else {
            return nil
        }

        let variantCode = person.placeholder(for: variant)
        let primaryText = person.text(for: variant)  // Use primary's text, not alias
        mappings[aliasKey] = (original: primaryText, replacement: variantCode)

        #if DEBUG
        print("EntityMapping.completeMergeWithVariant: '\(alias)' → \(variantCode) (user selected: \(variant), restores to: '\(primaryText)')")
        #endif

        return variantCode
    }

    /// Update or create a RedactedPerson structure for an entity
    /// Used when user manually edits name components via the Edit Name Structure modal
    /// - Parameters:
    ///   - replacementCode: The entity's replacement code (e.g., "[PERSON_A_FIRST_LAST]")
    ///   - firstName: The first name component
    ///   - middleName: The middle name component (optional)
    ///   - lastName: The last name component
    ///   - title: The title (Mr, Mrs, Dr, etc.) - optional
    func updatePersonStructure(
        replacementCode: String,
        firstName: String,
        middleName: String?,
        lastName: String,
        title: String?
    ) {
        // Extract baseId from replacement code
        guard let baseId = extractBaseId(from: replacementCode) else {
            #if DEBUG
            print("EntityMapping.updatePersonStructure: Could not extract baseId from '\(replacementCode)'")
            #endif
            return
        }

        // Build full name from components
        var fullNameParts = [firstName]
        if let middle = middleName, !middle.isEmpty {
            fullNameParts.append(middle)
        }
        fullNameParts.append(lastName)
        let fullName = fullNameParts.joined(separator: " ")

        // Create RedactedPerson
        let person = RedactedPerson(
            baseId: baseId,
            full: fullName,
            first: firstName,
            last: lastName,
            middle: middleName?.isEmpty == true ? nil : middleName,
            detectedTitle: title?.isEmpty == true ? nil : title
        )

        // Store in redactedPersons dictionary
        redactedPersons[baseId] = person

        // Update mappings for all name variants
        updateMappingsForPerson(person)

        #if DEBUG
        print("EntityMapping.updatePersonStructure: Updated '\(baseId)' with first='\(firstName)', middle='\(middleName ?? "nil")', last='\(lastName)'")
        #endif
    }

    /// Update all mappings for a RedactedPerson's name variants
    private func updateMappingsForPerson(_ person: RedactedPerson) {
        // Build list of variant -> text pairs
        var variants: [(NameVariant, String)] = [
            (.first, person.first),
            (.last, person.last),
            (.firstLast, person.firstLast),
            (.full, person.full)
        ]

        // Add middle name variants if present
        if let middle = person.middle, !middle.isEmpty {
            variants.append((.middle, middle))
            if let firstMiddle = person.firstMiddle {
                variants.append((.firstMiddle, firstMiddle))
            }
        }

        // Add formal variant if title is present
        if person.detectedTitle != nil {
            variants.append((.formal, person.formal))
        }

        // Update mappings for each variant
        for (variant, text) in variants where !text.isEmpty {
            let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let code = person.placeholder(for: variant)
            mappings[key] = (original: text, replacement: code)
        }
    }

    /// Get the RedactedPerson for an entity's replacement code (if exists)
    func getPersonForCode(_ replacementCode: String) -> RedactedPerson? {
        guard let baseId = extractBaseId(from: replacementCode) else {
            return nil
        }
        return redactedPersons[baseId]
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
