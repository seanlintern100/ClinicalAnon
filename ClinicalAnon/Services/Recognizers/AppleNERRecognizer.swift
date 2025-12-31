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
class AppleNERRecognizer: EntityRecognizer {

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

            let name = String(text[range])

            // Skip if it's a common word (not actually a name)
            guard !isCommonWord(name) else { return true }

            // Skip clinical abbreviations and terms (cause false positives)
            guard !isClinicalTerm(name) else { return true }

            // Skip user-excluded words
            guard !isUserExcluded(name) else { return true }

            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)

            // Map Apple's tag types to our EntityType
            let entityType: EntityType? = mapAppleTag(tag, text: name)

            if let type = entityType {
                entities.append(Entity(
                    originalText: name,
                    replacementCode: "",
                    type: type,
                    positions: [[start, end]],
                    confidence: 0.7  // Apple NER baseline confidence
                ))
            }

            return true  // Continue enumeration
        }

        // Extend names with following surnames (Hayden → Hayden Hooper)
        let extendedForward = extendWithSurnames(entities, in: text)

        // Extend names with preceding first names (Fletcher → Sue Fletcher)
        let extendedBoth = extendWithFirstNames(extendedForward, in: text)

        return extendedBoth
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

    // MARK: - First Name Extension (Backward)

    /// Extend detected surnames with preceding first names
    /// Example: "Fletcher" detected, preceded by "Sue" → extend to "Sue Fletcher"
    private func extendWithFirstNames(_ entities: [Entity], in text: String) -> [Entity] {
        var result: [Entity] = []

        for entity in entities {
            // Only extend person names
            guard entity.type.isPerson else {
                result.append(entity)
                continue
            }

            guard let position = entity.positions.first,
                  position.count >= 2 else {
                result.append(entity)
                continue
            }

            let entityStart = position[0]

            // Check if there's a preceding word that could be a first name
            if let firstName = findPrecedingFirstName(before: entityStart, in: text) {
                let extendedStart = entityStart - firstName.count - 1 // -1 for space
                let extendedEntity = Entity(
                    originalText: firstName + " " + entity.originalText,
                    replacementCode: "",
                    type: entity.type,
                    positions: [[extendedStart, position[1]]],
                    confidence: entity.confidence
                )
                result.append(extendedEntity)

                #if DEBUG
                print("  ✓ Extended '\(entity.originalText)' backward to '\(firstName) \(entity.originalText)'")
                #endif
            } else {
                result.append(entity)
            }
        }

        return result
    }

    /// Find a first name preceding a surname at the given position
    private func findPrecedingFirstName(before startIndex: Int, in text: String) -> String? {
        guard startIndex > 1 else { return nil }

        let idx = text.index(text.startIndex, offsetBy: startIndex)

        // Check if preceded by a space
        let beforeIdx = text.index(before: idx)
        guard beforeIdx >= text.startIndex, text[beforeIdx] == " " else { return nil }

        // Find the start of the preceding word by walking backwards
        var wordStart = beforeIdx
        while wordStart > text.startIndex {
            let prevIdx = text.index(before: wordStart)
            if text[prevIdx].isLetter {
                wordStart = prevIdx
            } else {
                break
            }
        }

        guard wordStart < beforeIdx else { return nil }

        let precedingWord = String(text[wordStart..<beforeIdx])

        // Check if it looks like a first name:
        // - Starts with uppercase
        // - 2+ characters
        // - Not a common word, clinical term, or user-excluded
        guard precedingWord.count >= 2,
              precedingWord.first?.isUppercase == true,
              !isCommonWord(precedingWord),
              !isClinicalTerm(precedingWord),
              !isUserExcluded(precedingWord) else {
            return nil
        }

        return precedingWord
    }

    // MARK: - Helper Methods

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
