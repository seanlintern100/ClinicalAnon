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

    // MARK: - Shared Instance

    /// Shared instance for deep scan access
    static let shared = SwiftNERService()

    // MARK: - Properties

    private let recognizers: [EntityRecognizer]

    // MARK: - Initialization

    init() {
        // Initialize all recognizers
        // Order matters: emails first (whole units), then specific patterns, names last
        var allRecognizers: [EntityRecognizer] = [
            EmailRecognizer(),             // Emails FIRST - whole units, reduces parsing
            NZPhoneRecognizer(),           // NZ phone numbers
            NZMedicalIDRecognizer(),       // NHI, ACC case numbers
            DateRecognizer(),              // Date patterns
            NZAddressRecognizer(),         // NZ addresses and suburbs
            MaoriNameRecognizer(),         // NZ-specific Māori names
            RelationshipNameExtractor(),   // Extract names from "sister Margaret"
            TitleNameRecognizer(),         // Extract names from "Mr Ronald", "Dr Smith"
            AppleNERRecognizer()           // Apple's baseline NER (names) last
        ]

        // Add catch-all number recognizer if enabled (default: ON)
        let redactAllNumbers = UserDefaults.standard.object(forKey: SettingsKeys.redactAllNumbers) as? Bool ?? true
        if redactAllNumbers {
            allRecognizers.append(AllNumbersRecognizer())
        }

        self.recognizers = allRecognizers

        #if DEBUG
        print("🔧 Initialized SwiftNERService with \(recognizers.count) recognizers (redactAllNumbers: \(redactAllNumbers))")
        #endif
    }

    // MARK: - Entity Detection (Two-Phase Chunked Architecture)

    /// Detect entities in the given text using chunked parallel processing
    /// - Parameter text: The clinical text to analyze
    /// - Returns: Array of detected entities
    func detectEntities(in text: String) async throws -> [Entity] {
        let startTime = Date()

        #if DEBUG
        print("🔍 SwiftNER: Starting entity detection...")
        print("📝 Input text length: \(text.count) chars")
        #endif

        // PHASE 1: Chunked detection with parallel processing
        let chunks = ChunkManager.splitWithOverlap(text)
        var allEntities: [Entity] = []

        #if DEBUG
        print("📦 Processing \(chunks.count) chunks in parallel...")
        #endif

        // Process chunks in parallel using TaskGroup
        await withTaskGroup(of: (Int, [Entity]).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let entities = self.processChunk(chunk)
                    return (index, entities)
                }
            }

            // Collect results (order doesn't matter, we sort later)
            for await (_, chunkEntities) in group {
                allEntities.append(contentsOf: chunkEntities)
            }
        }

        #if DEBUG
        print("📦 Phase 1 complete: \(allEntities.count) raw entities from chunks")
        #endif

        // Remove overlaps (keeps longer, higher-confidence entities)
        let noOverlaps = removeOverlaps(allEntities)

        // Deduplicate (merges same-text entities from overlap regions)
        let deduplicated = deduplicateEntities(noOverlaps)

        // Validate positions are within text bounds
        let validated = validateEntityPositions(deduplicated, textLength: text.count)

        // PHASE 2: Single-pass occurrence scan for all names
        let withAllOccurrences = singlePassOccurrenceScan(validated, in: text)

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ SwiftNER: Completed in \(String(format: "%.2f", elapsed))s (\(withAllOccurrences.count) entities)")
        #endif

        return withAllOccurrences
    }

    // MARK: - Deep Scan (Apple NER at Lower Confidence)

    /// Run Apple NER with lower confidence threshold to catch entities missed by initial scan
    /// - Parameters:
    ///   - text: The text to scan
    ///   - existingEntities: Entities already detected (to avoid duplicates)
    /// - Returns: Array of new PIIFindings not already in existingEntities
    func runDeepScan(text: String, existingEntities: [Entity]) async -> [PIIFinding] {
        let startTime = Date()

        #if DEBUG
        print("🔍 Deep Scan: Starting Apple NER at 0.75 confidence...")
        print("📝 Input text length: \(text.count) chars")
        print("📋 Existing entities to compare against: \(existingEntities.count)")
        #endif

        // Create Apple NER recognizer with lower confidence threshold
        let deepScanRecognizer = AppleNERRecognizer(minConfidence: 0.75)

        // PHASE 1: Chunked detection (same as main scan)
        let chunks = ChunkManager.splitWithOverlap(text)
        var allEntities: [Entity] = []

        #if DEBUG
        print("📦 Processing \(chunks.count) chunks...")
        #endif

        // Process chunks in parallel
        await withTaskGroup(of: (Int, [Entity]).self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    let entities = deepScanRecognizer.recognize(in: chunk.text)

                    // Adjust positions from chunk-local to global coordinates
                    var adjustedEntities: [Entity] = []
                    for entity in entities {
                        if let adjustedPositions = ChunkManager.adjustPositions(entity.positions, for: chunk) {
                            adjustedEntities.append(Entity(
                                id: entity.id,
                                originalText: entity.originalText,
                                replacementCode: entity.replacementCode,
                                type: entity.type,
                                positions: adjustedPositions,
                                confidence: entity.confidence
                            ))
                        }
                    }
                    return (index, adjustedEntities)
                }
            }

            for await (_, chunkEntities) in group {
                allEntities.append(contentsOf: chunkEntities)
            }
        }

        #if DEBUG
        print("📦 Phase 1 complete: \(allEntities.count) raw entities from chunks")
        #endif

        // Apply same cleanup as main scan
        let noOverlaps = removeOverlaps(allEntities)
        let deduplicated = deduplicateEntities(noOverlaps)
        let validated = validateEntityPositions(deduplicated, textLength: text.count)

        // PHASE 2: Single-pass occurrence scan
        let withAllOccurrences = singlePassOccurrenceScan(validated, in: text)

        // PHASE 3: Filter against existing entities (only return delta)
        let existingTexts = Set(existingEntities.map { $0.originalText.lowercased() })

        let newFindings = withAllOccurrences.compactMap { entity -> PIIFinding? in
            let normalizedText = entity.originalText.lowercased()

            // Skip if already exists in existing entities
            if existingTexts.contains(normalizedText) {
                return nil
            }

            // Skip if this is a substring of an existing entity or vice versa
            let isSubstringMatch = existingEntities.contains { existing in
                let existingLower = existing.originalText.lowercased()
                return existingLower.contains(normalizedText) || normalizedText.contains(existingLower)
            }

            if isSubstringMatch {
                return nil
            }

            return PIIFinding(
                text: entity.originalText,
                suggestedType: entity.type,
                reason: "Deep Scan (Apple NER 0.75)",
                confidence: entity.confidence ?? 0.75
            )
        }

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ Deep Scan: Completed in \(String(format: "%.2f", elapsed))s")
        print("   Found \(withAllOccurrences.count) total, \(newFindings.count) new (delta)")
        #endif

        return newFindings
    }

    // MARK: - Chunk Processing

    /// Process a single chunk through all recognizers
    private func processChunk(_ chunk: ChunkInfo) -> [Entity] {
        var chunkEntities: [Entity] = []

        for recognizer in recognizers {
            let entities = recognizer.recognize(in: chunk.text)

            // Adjust positions from chunk-local to global coordinates
            for entity in entities {
                if let adjustedPositions = ChunkManager.adjustPositions(entity.positions, for: chunk) {
                    chunkEntities.append(Entity(
                        id: entity.id,
                        originalText: entity.originalText,
                        replacementCode: entity.replacementCode,
                        type: entity.type,
                        positions: adjustedPositions,
                        confidence: entity.confidence
                    ))
                }
            }
        }

        return chunkEntities
    }

    // MARK: - Phase 2: Single-Pass Occurrence Scan

    /// Find all occurrences of detected names in a single pass through the text
    private func singlePassOccurrenceScan(_ entities: [Entity], in text: String) -> [Entity] {
        // Collect unique person name strings
        var nameSet: Set<String> = []
        var entityByName: [String: Entity] = [:]

        for entity in entities {
            guard entity.type.isPerson else { continue }

            let key = entity.originalText.lowercased()
            nameSet.insert(entity.originalText)
            entityByName[key] = entity

            #if DEBUG
            if entity.type.isPerson {
                print("  📋 Added to scan list: '\(entity.originalText)'")
            }
            #endif

            // Extract first name components from multi-word names
            let words = entity.originalText.split(separator: " ")
            if words.count >= 2 {
                let firstName = String(words[0])
                if firstName.count >= 3 && !isCommonWord(firstName) && !isClinicalTerm(firstName) {
                    nameSet.insert(firstName)
                }
            }
        }

        guard !nameSet.isEmpty else { return entities }

        // Build single regex for all names (longest first to prevent partial matches)
        // Also match possessive forms without apostrophe (e.g., "Sean" also matches "Seans")
        let sortedNames = nameSet.sorted { $0.count > $1.count }
        let escapedNames = sortedNames.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(" + escapedNames.joined(separator: "|") + ")s?\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return entities
        }

        // Single pass through text to find all occurrences
        let nsText = text as NSString
        var allPositions: [String: [[Int]]] = [:]

        let range = NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let matchedText = nsText.substring(with: match.range)
            let key = matchedText.lowercased()
            let position = [match.range.location, match.range.location + match.range.length]
            allPositions[key, default: []].append(position)
        }

        // Build result with complete position lists
        var result: [Entity] = []
        var processedKeys: Set<String> = []

        // Update existing entities with all positions found
        for entity in entities {
            if entity.type.isPerson {
                let key = entity.originalText.lowercased()
                if let positions = allPositions[key], !processedKeys.contains(key) {
                    result.append(Entity(
                        id: entity.id,
                        originalText: entity.originalText,
                        replacementCode: entity.replacementCode,
                        type: entity.type,
                        positions: positions,
                        confidence: entity.confidence
                    ))
                    processedKeys.insert(key)
                } else if !processedKeys.contains(key) {
                    // Name wasn't found in scan (edge case) - keep original
                    result.append(entity)
                    processedKeys.insert(key)
                }
            } else {
                // Non-person entities pass through unchanged
                result.append(entity)
            }
        }

        // Add extracted first names that were found
        for (key, positions) in allPositions {
            guard !processedKeys.contains(key) else { continue }

            // Find parent entity for type/replacement code inheritance
            let parentEntity = entities.first { entity in
                entity.type.isPerson && entity.originalText.lowercased().hasPrefix(key + " ")
            }

            if let parent = parentEntity {
                result.append(Entity(
                    originalText: positions.first.map { nsText.substring(with: NSRange(location: $0[0], length: $0[1] - $0[0])) } ?? key.capitalized,
                    replacementCode: parent.replacementCode,
                    type: parent.type,
                    positions: positions,
                    confidence: parent.confidence
                ))
                processedKeys.insert(key)

                #if DEBUG
                print("  ✓ Extracted '\(key)' (\(positions.count) occurrences)")
                #endif
            }
        }

        return result
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
                return nil
            }

            // If some positions were invalid, create new entity with only valid positions
            if validPositions.count < entity.positions.count {
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

    /// Check if a word is a common English word (not a name)
    private func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            "the", "a", "an", "and", "but", "or", "nor", "for", "yet", "so",
            "in", "on", "at", "to", "from", "with", "by", "of", "about",
            "he", "she", "it", "they", "we", "you", "i",
            "him", "her", "them", "us", "me",
            "his", "its", "their", "our", "your", "my",
            "is", "was", "are", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            "this", "that", "these", "those",
            "when", "where", "what", "which", "who", "why", "how",
            "patient", "treatment", "therapy", "care", "health",
            "medical", "clinical", "hospital", "clinic", "doctor",
            "mother", "father", "sister", "brother", "son", "daughter",
            "wife", "husband", "partner", "friend", "family", "whanau"
        ]
        return commonWords.contains(word.lowercased())
    }

    /// Check if a word is a clinical term to exclude
    private func isClinicalTerm(_ word: String) -> Bool {
        let clinicalTerms: Set<String> = [
            "GP", "MDT", "AOD", "ACC", "DHB", "ED", "ICU", "OT", "PT",
            "CBT", "DBT", "ACT", "EMDR", "MI", "MH", "MHA", "MOH",
            "ADHD", "ADD", "ASD", "OCD", "PTSD", "GAD", "MDD", "BPD",
            "DSM", "ICD", "Dx", "Rx", "Tx", "Hx", "Sx", "PRN",
            "TBI", "CVA", "MS", "CP", "LD", "ID", "ABI",
            "NGO", "MOE", "MSD", "WINZ", "CYF",
            "NZ", "USA", "UK", "AU",
            "Client", "Supplier", "Provider", "Participant", "Claimant",
            "Referrer", "Coordinator", "Author", "Reviewer", "Approver",
            "Name", "Address", "Phone", "Email", "Contact", "Details",
            "Number", "Date", "Claim", "Reference", "Report", "File",
            "Current", "Background", "History", "Plan", "Goals", "Progress",
            "Summary", "Recommendations", "Actions", "Notes", "Comments"
        ]
        return clinicalTerms.contains(word) || clinicalTerms.contains(word.uppercased())
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
