//
//  AppleNERRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Wraps Apple's NaturalLanguage framework for baseline NER
//  Organization: 3 Big Things
//

import Foundation
import NaturalLanguage

// MARK: - Apple NER Recognizer

/// Uses Apple's built-in Named Entity Recognition
/// Provides baseline detection for common English names, places, and organizations
/// Note: Chunking is handled by SwiftNERService - this recognizer receives pre-chunked text
class AppleNERRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Minimum confidence threshold for entity detection
    /// Default: 0.85 for initial scan, can be lowered (e.g., 0.75) for deep scan
    private let minConfidence: Double

    // MARK: - Initialization

    init(minConfidence: Double = 0.85) {
        self.minConfidence = minConfidence
    }

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        // Replace tabs with newlines so Apple NER treats columns as separate sentences
        // This prevents cross-column name joining and allows proper surname detection
        let processedText = text.replacingOccurrences(of: "\t", with: "\n")

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = processedText

        var entities: [Entity] = []

        // Enumerate tags in the text
        tagger.enumerateTags(
            in: processedText.startIndex..<processedText.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in

            guard let tag = tag else { return true }

            // Get actual confidence from NLTagger
            let (hypotheses, _) = tagger.tagHypotheses(
                at: range.lowerBound,
                unit: .word,
                scheme: .nameType,
                maximumCount: 1
            )

            let name = String(processedText[range])
            let confidence = hypotheses[tag.rawValue] ?? 0.0

            // Require minimum confidence to reduce false positives
            guard confidence >= minConfidence else {
                return true  // Skip low-confidence predictions
            }

            // Skip multi-word "names" with invalid middle words (e.g., "Person asked Other")
            guard !hasInvalidMiddleWord(name) else { return true }

            // Skip if it's a common word (not actually a name)
            guard !isCommonWord(name) else { return true }

            // Skip clinical abbreviations and terms (cause false positives)
            guard !isClinicalTerm(name) else { return true }

            // Skip user-excluded words
            guard !isUserExcluded(name) else { return true }

            // Use NSString for fast O(1) offset calculation
            // Positions are same since \t and \n are both single chars
            let nsText = processedText as NSString
            let nsRange = NSRange(range, in: processedText)
            let start = nsRange.location
            let end = nsRange.location + nsRange.length

            // Map Apple's tag types to our EntityType
            let entityType: EntityType? = mapAppleTag(tag, text: name)

            if let type = entityType {
                entities.append(Entity(
                    originalText: name,
                    replacementCode: "",
                    type: type,
                    positions: [[start, end]],
                    confidence: confidence  // Actual confidence from NLTagger
                ))
            }

            return true  // Continue enumeration
        }

        // Extend names with following surnames (FirstName → FirstName Surname)
        let extendedEntities = extendWithSurnames(entities, in: processedText)

        // Second pass: use known surnames to extend remaining first names
        // e.g., if "Person A Surname" was detected, use "Surname" to extend "Person B" → "Person B Surname"
        let withKnownSurnames = extendWithKnownSurnames(extendedEntities, in: processedText)

        // Extend with name-words (e.g., common words that are also names)
        let withNameWords = extendWithNameWords(withKnownSurnames, in: processedText)

        return withNameWords
    }

    // MARK: - Name-Word List

    /// Name particles that are valid lowercase middle words in multi-word names
    /// e.g., "Person van Name", "Person da Name"
    private let nameParticles: Set<String> = [
        "von", "van", "de", "da", "del", "della", "di", "du",
        "la", "le", "los", "las",
        "bin", "ibn", "al", "el",
    ]

    /// Words that are both common words AND valid first names
    /// Only matched when capitalized and NOT at sentence start
    private let nameWords: Set<String> = [
        // Legal/action words that are also names
        "sue", "will", "bill", "grant", "mark", "pat", "rob", "drew",
        "chase", "pierce", "wade", "earnest", "payton",
        // Month names
        "april", "may", "june",
        // Virtue/nature names
        "hope", "joy", "faith", "grace", "rose", "belle", "dawn",
        "sky", "skye", "rain", "reign", "ash", "clay", "reed", "reid",
        "lane", "brook", "brooke", "blair", "sage",
        // Other common word-names
        "guy", "herb", "gene", "earl", "dean"
    ]

    // MARK: - Name-Word Extension

    /// Extend detected names with preceding words from name-word list
    /// Only extends if word is capitalized AND not at sentence start
    private func extendWithNameWords(_ entities: [Entity], in text: String) -> [Entity] {
        var result: [Entity] = []

        for entity in entities {
            guard entity.type.isPerson else {
                result.append(entity)
                continue
            }

            guard let position = entity.positions.first, position.count >= 2 else {
                result.append(entity)
                continue
            }

            let entityStart = position[0]

            if let nameWord = findPrecedingNameWord(before: entityStart, in: text) {
                let extendedStart = entityStart - nameWord.count - 1
                result.append(Entity(
                    originalText: nameWord + " " + entity.originalText,
                    replacementCode: "",
                    type: entity.type,
                    positions: [[extendedStart, position[1]]],
                    confidence: entity.confidence
                ))
            } else {
                result.append(entity)
            }
        }
        return result
    }

    /// Find a name-word preceding the entity
    /// Must be: in list, capitalized, NOT at sentence start
    private func findPrecedingNameWord(before startIndex: Int, in text: String) -> String? {
        guard startIndex > 2 else { return nil }

        let idx = text.index(text.startIndex, offsetBy: startIndex)
        let beforeIdx = text.index(before: idx)
        guard text[beforeIdx] == " " else { return nil }

        // Find the start of the preceding word
        var wordStart = beforeIdx
        while wordStart > text.startIndex {
            let prevIdx = text.index(before: wordStart)
            if text[prevIdx].isLetter { wordStart = prevIdx }
            else { break }
        }

        guard wordStart < beforeIdx else { return nil }
        let word = String(text[wordStart..<beforeIdx])

        // Must be in name-word list
        guard nameWords.contains(word.lowercased()) else { return nil }

        // Must be capitalized
        guard word.first?.isUppercase == true else { return nil }

        // Must NOT be at sentence start (check what's before the word)
        if wordStart > text.startIndex {
            let charBeforeWord = text.index(before: wordStart)
            let prevChar = text[charBeforeWord]
            // If preceded by period, newline, or bullet, it's sentence start - skip
            if prevChar == "." || prevChar == "\n" || prevChar == "•" || prevChar == "-" {
                return nil
            }
            // If preceded by ": " or "- " it's likely a list item start
            if prevChar == ":" || prevChar == ";" {
                return nil
            }
        } else {
            // At very start of text - sentence start
            return nil
        }

        return word
    }

    // MARK: - Surname Extension

    /// Extend detected first names with following capitalized words (likely surnames)
    /// Scans ALL occurrences of each name in text to find surname opportunities
    /// Example: "FirstName" detected, find occurrence followed by "Surname" → extend to "FirstName Surname"
    private func extendWithSurnames(_ entities: [Entity], in text: String) -> [Entity] {
        var result: [Entity] = []

        for entity in entities {
            // Only extend person names
            guard entity.type == .personOther ||
                  entity.type == .personClient ||
                  entity.type == .personProvider else {
                result.append(entity)
                continue
            }

            // Skip if already multi-word (already has surname)
            if entity.originalText.contains(" ") {
                result.append(entity)
                continue
            }

            // Find ALL occurrences of this first name in text to find a surname
            if let surname = findSurnameForName(entity.originalText, in: text) {
                let extendedEntity = Entity(
                    originalText: entity.originalText + " " + surname,
                    replacementCode: "",
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

    /// Second pass: extend first names using known surnames from already-detected full names
    /// e.g., if "Person A Surname" was detected, "Surname" becomes known
    /// Then "Person B" can be extended to "Person B Surname" if followed by same surname in text
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

            // Check if this first name is followed by a known surname
            if let surname = findKnownSurnameAfter(entity.originalText, knownSurnames: knownSurnames, in: text) {
                let extendedEntity = Entity(
                    originalText: entity.originalText + " " + surname,
                    replacementCode: "",
                    type: entity.type,
                    positions: entity.positions,
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
        // Build pattern: firstName followed by space and capitalized word
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

    /// Search all occurrences of firstName in text to find one followed by a surname
    private func findSurnameForName(_ firstName: String, in text: String) -> String? {
        // Build pattern: firstName followed by SPACE ONLY (not any whitespace)
        // This respects tab→newline conversion as column separators
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
            let surname = nsText.substring(with: surnameRange)

            // Validate surname
            guard surname.count >= 2,
                  !isCommonWord(surname),
                  !isClinicalTerm(surname),
                  !isUserExcluded(surname) else {
                continue
            }

            return surname
        }

        return nil
    }

    // MARK: - Helper Methods

    // MARK: - Multi-Word Name Validation

    /// Check if multi-word name has invalid middle words
    /// Valid middle words: capitalized OR known name particle (von, de, van, etc.)
    /// Rejects: "Person asked Other" (asked is lowercase, not a particle)
    /// Accepts: "First Middle Last" (Middle is capitalized)
    /// Accepts: "Person van Name" (van is a particle)
    private func hasInvalidMiddleWord(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count > 2 else { return false }  // Only check 3+ word names

        // Check middle words (skip first and last)
        for word in words.dropFirst().dropLast() {
            let wordStr = String(word)

            // If lowercase and NOT a name particle → invalid
            if wordStr.first?.isLowercase == true {
                if !nameParticles.contains(wordStr.lowercased()) {
                    return true  // Invalid - lowercase non-particle
                }
            }
        }
        return false
    }

    /// Map Apple's NLTag to our EntityType
    private func mapAppleTag(_ tag: NLTag, text: String) -> EntityType? {
        switch tag {
        case .personalName:
            // Default to personOther - will be refined by other recognizers
            return .personOther

        case .placeName:
            return .location

        case .organizationName:
            return .organization

        default:
            return nil
        }
    }
}
