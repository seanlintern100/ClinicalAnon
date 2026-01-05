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

        // Use NSString for fast O(1) offset access (UTF-16 based)
        let nsText = text as NSString

        for (pattern, type, confidence) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                print("⚠️ Invalid regex pattern: \(pattern)")
                continue
            }

            let range = NSRange(location: 0, length: nsText.length)
            let matches = regex.matches(in: text, range: range)

            for match in matches {
                let matched = nsText.substring(with: match.range)
                // Use UTF-16 offsets directly - fast O(1) access
                let start = match.range.location
                let end = match.range.location + match.range.length

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
        let nsText = text as NSString
        var searchStart = 0

        let options: NSString.CompareOptions = caseInsensitive ? [.caseInsensitive] : []

        while searchStart < nsText.length {
            let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
            let foundRange = nsText.range(of: word, options: options, range: searchRange)

            if foundRange.location == NSNotFound { break }

            positions.append([foundRange.location, foundRange.location + foundRange.length])
            searchStart = foundRange.location + foundRange.length
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
        // All terms stored in lowercase for case-insensitive matching
        let clinicalTerms: Set<String> = [
            // Common clinical abbreviations
            "gp", "mdt", "aod", "a&d", "acc", "dhb", "ed", "icu", "ot", "pt",
            "cbt", "dbt", "act", "emdr", "mi", "mh", "mha", "moh", "doh",
            "camhs", "catt", "cat", "crisis", "eap", "eps", "ect",
            // Mental health conditions
            "adhd", "add", "asd", "ocd", "ptsd", "gad", "mdd", "bpd", "npd",
            // Assessment tools
            "bai", "bdi", "phq", "gad7", "k10", "dass", "wais", "wisc",
            // Medical abbreviations
            "dsm", "icd", "dx", "rx", "tx", "hx", "sx", "prn", "qid", "tds", "bd",
            // Injury/condition abbreviations
            "tbi", "cva", "ms", "cp", "ld", "id", "abi",
            // NZ Government/org abbreviations
            "ngo", "moe", "msd", "winz", "cyf", "senco",
            // Support groups
            "aa", "na", "ca", "ga", "saa", "slaa",
            // AOD specific
            "aods", "cads", "dapaanz",
            // Business abbreviations
            "fte", "pte", "ceo", "gm", "hr",
            // Country/region codes
            "nz", "usa", "uk", "au", "nsw", "vic", "qld",
            // Common abbreviations
            "td", "tt", "tbc", "tba", "asap", "fyi", "nb", "ps", "re",
            // Medications that get flagged as names
            "methadone", "suboxone", "ritalin", "dexamphetamine",
            "antidepressant", "antipsychotic", "anxiolytic", "benzodiazepine",
            "turps", "cannabis", "methamphetamine", "amphetamine",
            // Clinical roles/terms
            "specialist", "registrar", "consultant", "clinician",
            "timeline", "formulation", "assessment", "intervention",
            // Section headers that get flagged
            "current", "background", "history", "plan", "goals", "progress",
            "summary", "recommendations", "actions", "notes", "comments",
            "rehab", "reports",
            // Form field labels (not person names)
            "client", "supplier", "provider", "participant", "claimant",
            "referrer", "coordinator", "author", "reviewer", "approver",
            "name", "address", "phone", "email", "contact", "details",
            "number", "date", "claim", "reference", "ref", "report", "file"
        ]

        return clinicalTerms.contains(word.lowercased())
    }
}
