//
//  UserInclusionRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Recognizer for user-specified words that should always be flagged as PII
//  Organization: 3 Big Things
//

import Foundation

// MARK: - User Inclusion Recognizer

/// Recognizer that finds all occurrences of user-specified inclusion words
/// Each word is flagged with the type specified by the user
class UserInclusionRecognizer: EntityRecognizer {

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        let inclusions = UserInclusionManager.shared.inclusions
        guard !inclusions.isEmpty else { return [] }

        var entities: [Entity] = []

        for inclusion in inclusions {
            let positions = findOccurrences(of: inclusion.word, in: text, caseInsensitive: true)
            guard !positions.isEmpty else { continue }

            // Check if this word is excluded by user
            guard !isUserExcluded(inclusion.word) else { continue }

            entities.append(Entity(
                originalText: inclusion.word,
                replacementCode: "",  // Will be assigned by EntityMapping
                type: inclusion.type,
                positions: positions,
                confidence: 1.0  // User-specified = high confidence
            ))
        }

        return entities
    }
}
