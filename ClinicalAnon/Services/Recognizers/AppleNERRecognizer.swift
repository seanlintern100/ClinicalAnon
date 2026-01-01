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
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [Entity] = []

        // Enumerate tags in the text
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
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

            let name = String(text[range])
            let confidence = hypotheses[tag.rawValue] ?? 0.0

            // Require minimum confidence to reduce false positives
            guard confidence >= minConfidence else {
                return true  // Skip low-confidence predictions
            }

            // Skip multi-word "names" with invalid middle words (e.g., "John asked Mary")
            guard !hasInvalidMiddleWord(name) else { return true }

            // Skip if it's a common word (not actually a name)
            guard !isCommonWord(name) else { return true }

            // Skip clinical abbreviations and terms (cause false positives)
            guard !isClinicalTerm(name) else { return true }

            // Skip user-excluded words
            guard !isUserExcluded(name) else { return true }

            // Use NSString for fast O(1) offset calculation
            let nsText = text as NSString
            let nsRange = NSRange(range, in: text)
            let start = nsRange.location
            let end = nsRange.location + nsRange.length

            // Map Apple's tag types to our EntityType
            let entityType: EntityType? = mapAppleTag(tag, text: name)

            if let type = entityType {
                #if DEBUG
                print("  🏷️ Apple NER: '\(name)' → \(type) (confidence: \(String(format: "%.2f", confidence)))")
                #endif
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

        // Extend names with following surnames (Hayden → Hayden Hooper)
        let extendedEntities = extendWithSurnames(entities, in: text)

        // Extend with name-words (Sue Fletcher, May Johnson)
        let withNameWords = extendWithNameWords(extendedEntities, in: text)

        return withNameWords
    }

    // MARK: - Name-Word List

    /// Name particles that are valid lowercase middle words in multi-word names
    /// e.g., "Ludwig van Beethoven", "Leonardo da Vinci"
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

                #if DEBUG
                print("  ✓ Extended '\(entity.originalText)' with name-word '\(nameWord)'")
                #endif
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
    /// Example: "Hayden" detected, followed by "Hooper" → extend to "Hayden Hooper"
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

            guard let position = entity.positions.first,
                  position.count >= 2 else {
                result.append(entity)
                continue
            }

            let entityEnd = position[1]

            // Check if there's a following word that could be a surname
            if let extendedName = findFollowingSurname(after: entityEnd, in: text, firstName: entity.originalText) {
                let extendedEnd = entityEnd + 1 + extendedName.count // +1 for space
                let extendedEntity = Entity(
                    originalText: entity.originalText + " " + extendedName,
                    replacementCode: "",
                    type: entity.type,
                    positions: [[position[0], extendedEnd]],
                    confidence: entity.confidence
                )
                result.append(extendedEntity)
            } else {
                result.append(entity)
            }
        }

        return result
    }

    /// Find a surname following a first name at the given position
    private func findFollowingSurname(after endIndex: Int, in text: String, firstName: String) -> String? {
        guard endIndex < text.count else { return nil }

        let startIdx = text.index(text.startIndex, offsetBy: endIndex)

        // Check if followed by a space
        guard startIdx < text.endIndex, text[startIdx] == " " else { return nil }

        // Get the next word
        let afterSpace = text.index(after: startIdx)
        guard afterSpace < text.endIndex else { return nil }

        // Find the end of the next word
        var wordEnd = afterSpace
        while wordEnd < text.endIndex && text[wordEnd].isLetter {
            wordEnd = text.index(after: wordEnd)
        }

        guard wordEnd > afterSpace else { return nil }

        let nextWord = String(text[afterSpace..<wordEnd])

        // Check if it looks like a surname:
        // - Starts with uppercase
        // - At least 2 characters
        // - Not a common word or clinical term
        guard nextWord.count >= 2,
              nextWord.first?.isUppercase == true,
              !isCommonWord(nextWord),
              !isClinicalTerm(nextWord),
              !isUserExcluded(nextWord) else {
            return nil
        }

        return nextWord
    }

    // MARK: - Helper Methods

    // MARK: - Multi-Word Name Validation

    /// Check if multi-word name has invalid middle words
    /// Valid middle words: capitalized OR known name particle (von, de, van, etc.)
    /// Rejects: "Liesbet asked Sean" (asked is lowercase, not a particle)
    /// Accepts: "Mary Jane Watson" (Jane is capitalized)
    /// Accepts: "Ludwig van Beethoven" (van is a particle)
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
