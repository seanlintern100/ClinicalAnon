//
//  EntityRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Protocol for entity recognition implementations
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Entity Recognizer Protocol

/// Protocol for all entity recognizers
/// Each recognizer scans text and returns detected entities
protocol EntityRecognizer {
    /// Recognize entities in the given text
    /// - Parameter text: The text to scan for entities
    /// - Returns: Array of detected entities
    func recognize(in text: String) -> [Entity]
}

// MARK: - Pattern Recognizer Base Class

/// Base class for regex-based entity recognizers
/// Subclass and provide patterns to implement specific recognizers
class PatternRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Array of (pattern, entityType, confidence) tuples
    let patterns: [(pattern: String, type: EntityType, confidence: Double)]

    // MARK: - Initialization

    init(patterns: [(String, EntityType, Double)]) {
        self.patterns = patterns
    }

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        for (pattern, type, confidence) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                print("⚠️ Invalid regex pattern: \(pattern)")
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }

                let matched = String(text[range])
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let end = text.distance(from: text.startIndex, to: range.upperBound)

                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "", // Will be assigned by EntityMapping
                    type: type,
                    positions: [[start, end]],
                    confidence: confidence
                ))
            }
        }

        return entities
    }
}

// MARK: - Helper Extensions

extension EntityRecognizer {
    /// Check if a word is in the user's exclusion list
    func isUserExcluded(_ word: String) -> Bool {
        return UserExclusionManager.shared.isExcluded(word)
    }

    /// Helper to find all occurrences of a word in text
    func findOccurrences(of word: String, in text: String, caseInsensitive: Bool = false) -> [[Int]] {
        var positions: [[Int]] = []
        var searchRange = text.startIndex..<text.endIndex

        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []

        while let range = text.range(of: word, options: options, range: searchRange) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            positions.append([start, end])

            searchRange = range.upperBound..<text.endIndex
        }

        return positions
    }

    /// Check if a word is a common English word to exclude
    func isCommonWord(_ word: String) -> Bool {
        let commonWords: Set<String> = [
            // Articles
            "the", "a", "an",
            // Conjunctions
            "and", "but", "or", "nor", "for", "yet", "so",
            // Prepositions
            "in", "on", "at", "to", "from", "with", "by", "for", "of", "about",
            // Pronouns
            "he", "she", "it", "they", "we", "you", "i",
            "him", "her", "them", "us", "me",
            "his", "her", "its", "their", "our", "your", "my",
            // Common verbs
            "is", "was", "are", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            // Other common words
            "this", "that", "these", "those",
            "when", "where", "what", "which", "who", "why", "how",
            // Medical/clinical common words
            "patient", "treatment", "therapy", "care", "health",
            "medical", "clinical", "hospital", "clinic", "doctor",
            // Relationship words (already filtered by RelationshipNameExtractor)
            "mother", "father", "sister", "brother", "son", "daughter",
            "wife", "husband", "partner", "friend", "family", "whanau"
        ]

        return commonWords.contains(word.lowercased())
    }

    /// Check if a word is a clinical abbreviation or term to exclude
    /// These are common in psychology/mental health notes and cause false positives
    func isClinicalTerm(_ word: String) -> Bool {
        let clinicalTerms: Set<String> = [
            // Common clinical abbreviations
            "GP", "MDT", "AOD", "A&D", "ACC", "DHB", "ED", "ICU", "OT", "PT",
            "CBT", "DBT", "ACT", "EMDR", "MI", "MH", "MHA", "MOH", "DOH",
            "CAMHS", "CATT", "CAT", "CRISIS", "EAP", "EPS", "ECT",
            // Mental health conditions
            "ADHD", "ADD", "ASD", "OCD", "PTSD", "GAD", "MDD", "BPD", "NPD",
            // Assessment tools
            "BAI", "BDI", "PHQ", "GAD7", "K10", "DASS", "WAIS", "WISC",
            // Medical abbreviations
            "DSM", "ICD", "Dx", "Rx", "Tx", "Hx", "Sx", "PRN", "QID", "TDS", "BD",
            // Injury/condition abbreviations
            "TBI", "CVA", "MS", "CP", "LD", "ID", "ABI",
            // NZ Government/org abbreviations
            "NGO", "MOE", "MSD", "WINZ", "CYF", "SENCO",
            // Support groups
            "AA", "NA", "CA", "GA", "SAA", "SLAA",
            // AOD specific
            "AODS", "CADS", "DAPAANZ",
            // Business abbreviations
            "FTE", "PTE", "CEO", "GM", "HR",
            // Country/region codes
            "NZ", "USA", "UK", "AU", "NSW", "VIC", "QLD",
            // Common abbreviations
            "TD", "TT", "TBC", "TBA", "ASAP", "FYI", "NB", "PS", "RE",
            // Medications that get flagged as names
            "Methadone", "Suboxone", "Ritalin", "Dexamphetamine",
            "Antidepressant", "Antipsychotic", "Anxiolytic", "Benzodiazepine",
            "Turps", "Cannabis", "Methamphetamine", "Amphetamine",
            // Clinical roles/terms
            "Specialist", "Registrar", "Consultant", "Clinician",
            "Timeline", "Formulation", "Assessment", "Intervention",
            // Section headers that get flagged
            "Current", "Background", "History", "Plan", "Goals", "Progress",
            "Summary", "Recommendations", "Actions", "Notes", "Comments",
            // Form field labels (not person names)
            "Client", "Supplier", "Provider", "Participant", "Claimant",
            "Referrer", "Coordinator", "Author", "Reviewer", "Approver",
            "Name", "Address", "Phone", "Email", "Contact", "Details",
            "Number", "Date", "Claim", "Reference", "Report", "File"
        ]

        return clinicalTerms.contains(word) || clinicalTerms.contains(word.uppercased())
    }
}
