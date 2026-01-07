//
//  SwiftNERService.swift
//  ClinicalAnon
//
//  Purpose: Swift-native entity recognition using Apple NER + custom NZ recognizers
//  Organization: 3 Big Things
//

import Foundation
import NaturalLanguage
import AppKit  // For NSSpellChecker

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
            TitleNameRecognizer(),         // Extract names from "Mr John", "Dr Smith"
            UserInclusionRecognizer(),     // User-specified PII words
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

        // Extend first names with known surnames (searches FULL text, not per-chunk)
        // This catches cases like "Jane" when "Smith" is known from "John Smith"
        let withSurnames = extendWithKnownSurnames(deduplicated, in: text)

        // Validate positions are within text bounds
        let validated = validateEntityPositions(withSurnames, textLength: text.count)

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

        // PHASE 4: Fuzzy matching for name misspellings
        let fuzzyFindings = findNameMisspellings(in: text, existingNames: existingEntities.filter { $0.type.isPerson })

        // PHASE 5: Non-word detection - capitalized words not in dictionary
        let nonWordFindings = findNonDictionaryWords(in: text, existingEntities: existingEntities, alreadyFound: newFindings + fuzzyFindings)

        // Combine findings
        let allFindings = newFindings + fuzzyFindings + nonWordFindings

        #if DEBUG
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ Deep Scan: Completed in \(String(format: "%.2f", elapsed))s")
        print("   Found \(withAllOccurrences.count) total, \(newFindings.count) new (delta), \(fuzzyFindings.count) fuzzy matches, \(nonWordFindings.count) non-words")
        #endif

        return allFindings
    }

    // MARK: - Fuzzy Name Matching

    /// Find potential misspellings of known names in text
    /// Uses Levenshtein distance to find words that are 1-2 edits away from known names
    private func findNameMisspellings(in text: String, existingNames: [Entity]) -> [PIIFinding] {
        // Collect unique name strings (first names and full names)
        var knownNames: Set<String> = []
        for entity in existingNames {
            let name = entity.originalText
            // Only consider names with 4+ characters for fuzzy matching (reduce false positives)
            if name.count >= 4 {
                knownNames.insert(name)
            }
            // Also add first names from multi-word names
            let words = name.split(separator: " ")
            if let firstName = words.first, firstName.count >= 4 {
                knownNames.insert(String(firstName))
            }
        }

        guard !knownNames.isEmpty else { return [] }

        // Extract capitalized words from text as candidates for misspelling check
        let wordPattern = "\\b[A-Z][a-z]{3,}\\b"  // Capitalized words, 4+ chars
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        var findings: [PIIFinding] = []
        var foundMisspellings: Set<String> = []

        // Already known names (exact matches to skip)
        let knownLower = Set(knownNames.map { $0.lowercased() })

        for match in matches {
            let word = nsText.substring(with: match.range)
            let wordLower = word.lowercased()

            // Skip if already a known name (exact match)
            if knownLower.contains(wordLower) { continue }

            // Skip if already found this misspelling
            if foundMisspellings.contains(wordLower) { continue }

            // Skip common words and clinical terms
            if NERUtilities.shouldExclude(word) { continue }

            // Check against each known name
            for knownName in knownNames {
                let distance = levenshteinDistance(wordLower, knownName.lowercased())

                // Accept if edit distance is 1-2 (depending on name length)
                let maxDistance = knownName.count >= 6 ? 2 : 1

                if distance > 0 && distance <= maxDistance {
                    #if DEBUG
                    print("  🔍 Fuzzy match: '\(word)' ≈ '\(knownName)' (distance: \(distance))")
                    #endif

                    findings.append(PIIFinding(
                        text: word,
                        suggestedType: .personOther,
                        reason: "Possible misspelling of '\(knownName)'",
                        confidence: 0.7
                    ))
                    foundMisspellings.insert(wordLower)
                    break  // Found a match, no need to check other names
                }
            }
        }

        return findings
    }

    // MARK: - Non-Dictionary Word Detection

    /// Find capitalized words that aren't in the system dictionary
    /// These are likely names, unusual proper nouns, or non-English words that should be reviewed
    private func findNonDictionaryWords(in text: String, existingEntities: [Entity], alreadyFound: [PIIFinding]) -> [PIIFinding] {
        let spellChecker = NSSpellChecker.shared

        // Build set of already-known texts to skip
        let existingTexts = Set(existingEntities.map { $0.originalText.lowercased() })
        let alreadyFoundTexts = Set(alreadyFound.map { $0.text.lowercased() })

        // Extract capitalized words (4+ chars to reduce noise)
        let wordPattern = "\\b[A-Z][a-z]{3,}\\b"
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        var findings: [PIIFinding] = []
        var foundWords: Set<String> = []

        for match in matches {
            let word = nsText.substring(with: match.range)
            let wordLower = word.lowercased()

            // Skip if already found or processed
            if existingTexts.contains(wordLower) { continue }
            if alreadyFoundTexts.contains(wordLower) { continue }
            if foundWords.contains(wordLower) { continue }

            // Skip common words and clinical terms
            if NERUtilities.shouldExclude(word) { continue }

            // Check if word is in dictionary using spell checker
            let misspelledRange = spellChecker.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)

            // If misspelledRange location is not NSNotFound, word is NOT in dictionary
            if misspelledRange.location != NSNotFound {
                foundWords.insert(wordLower)

                findings.append(PIIFinding(
                    text: word,
                    suggestedType: .personOther,  // Assume it's a name
                    reason: "Non-dictionary word (possible name)",
                    confidence: 0.6  // Lower confidence since it's speculative
                ))

                #if DEBUG
                print("  📖 Non-dictionary word: '\(word)'")
                #endif
            }
        }

        return findings
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        // Early termination if difference is too large
        if abs(m - n) > 2 { return abs(m - n) }

        if m == 0 { return n }
        if n == 0 { return m }

        // Use two rows instead of full matrix for memory efficiency
        var prevRow = Array(0...n)
        var currRow = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            currRow[0] = i

            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                currRow[j] = min(
                    prevRow[j] + 1,      // deletion
                    currRow[j - 1] + 1,  // insertion
                    prevRow[j - 1] + cost // substitution
                )
            }

            swap(&prevRow, &currRow)
        }

        return prevRow[n]
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

            // Extract first AND last name components from multi-word names
            let words = entity.originalText.split(separator: " ")
            if words.count >= 2 {
                // First name
                let firstName = String(words[0])
                if firstName.count >= 3 && !NERUtilities.shouldExclude(firstName) {
                    nameSet.insert(firstName)
                }
                // Last name (also important for possessives like "Versteeghs")
                if let lastName = words.last {
                    let lastNameStr = String(lastName)
                    if lastNameStr.count >= 3 && !NERUtilities.shouldExclude(lastNameStr) {
                        nameSet.insert(lastNameStr)
                    }
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

        // Build lowercase set for normalization
        let nameSetLower = Set(nameSet.map { $0.lowercased() })

        let range = NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match else { return }
            let matchedText = nsText.substring(with: match.range)
            var key = matchedText.lowercased()

            // Normalize possessive forms: if "seans" matched but "sean" is the known name, use "sean" as key
            // This ensures positions for "Seans" are stored under "sean" to match the entity lookup
            if key.hasSuffix("s") && !nameSetLower.contains(key) {
                let baseKey = String(key.dropLast())
                if nameSetLower.contains(baseKey) {
                    key = baseKey
                }
            }

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

        // Add extracted first/last names that were found
        for (key, positions) in allPositions {
            guard !processedKeys.contains(key) else { continue }

            // Find parent entity for type/replacement code inheritance
            // Check both first name (hasPrefix) and last name (hasSuffix)
            let parentEntity = entities.first { entity in
                guard entity.type.isPerson else { return false }
                let lowerName = entity.originalText.lowercased()
                return lowerName.hasPrefix(key + " ") || lowerName.hasSuffix(" " + key)
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

    // MARK: - Surname Extension (Full Text)

    /// Extend first names with known surnames from detected full names
    /// Runs on FULL text after chunk processing to catch cross-chunk matches
    private func extendWithKnownSurnames(_ entities: [Entity], in text: String) -> [Entity] {
        // Step 1: Collect known surnames from multi-word person names
        var knownSurnames: Set<String> = []
        for entity in entities {
            guard entity.type.isPerson else { continue }
            let words = entity.originalText.split(separator: " ")
            if words.count >= 2, let lastName = words.last {
                let surname = String(lastName)
                if surname.first?.isUppercase == true && surname.count >= 2 {
                    knownSurnames.insert(surname)
                }
            }
        }

        guard !knownSurnames.isEmpty else { return entities }

        // Step 2: For each single-word first name, check if followed by a known surname
        var result: [Entity] = []
        for entity in entities {
            guard entity.type.isPerson else {
                result.append(entity)
                continue
            }

            // Skip if already multi-word
            if entity.originalText.contains(" ") {
                result.append(entity)
                continue
            }

            // Check if this first name is followed by a known surname in the FULL text
            if let surname = findKnownSurnameAfter(entity.originalText, knownSurnames: knownSurnames, in: text) {
                let extendedEntity = Entity(
                    id: entity.id,
                    originalText: entity.originalText + " " + surname,
                    replacementCode: entity.replacementCode,
                    type: entity.type,
                    positions: entity.positions, // Will be recalculated in Phase 2
                    confidence: entity.confidence
                )
                result.append(extendedEntity)
            } else {
                result.append(entity)
            }
        }

        return result
    }

    /// Check if firstName is followed by any known surname in the text
    private func findKnownSurnameAfter(_ firstName: String, knownSurnames: Set<String>, in text: String) -> String? {
        // Pattern: firstName followed by space(s) and capitalized word
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: firstName)) +([A-Z][a-z]+)\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            let surnameRange = match.range(at: 1)
            let potentialSurname = nsText.substring(with: surnameRange)

            // Check if this is a known surname
            if knownSurnames.contains(potentialSurname) {
                return potentialSurname
            }
        }

        return nil
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

                // Prefer person type over location (Apple NER sometimes misclassifies names as places)
                // e.g., "Hayden" detected as location in one chunk, person in another
                let preferredType: EntityType
                if existing.type == .location && entity.type.isPerson {
                    preferredType = entity.type
                } else if entity.type == .location && existing.type.isPerson {
                    preferredType = existing.type
                } else {
                    // Otherwise keep existing type (first seen)
                    preferredType = existing.type
                }

                // Use the entity with higher confidence as the base, but keep all positions
                let merged = Entity(
                    id: existing.id,
                    originalText: existing.originalText,
                    replacementCode: existing.replacementCode,
                    type: preferredType,
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
