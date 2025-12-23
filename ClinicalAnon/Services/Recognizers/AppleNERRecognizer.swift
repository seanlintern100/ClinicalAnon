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

        return entities
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
