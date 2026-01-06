//
//  NERUtilities.swift
//  ClinicalAnon
//
//  Purpose: Shared utility functions for NER services
//  Organization: 3 Big Things
//

import Foundation

// MARK: - NER Utilities

/// Shared utilities for Named Entity Recognition services
/// Consolidates common filtering functions to ensure consistent behavior across all NER engines
enum NERUtilities {

    // MARK: - Common Word Filtering

    /// Check if a word is a common English word to exclude from entity detection
    /// Uses the comprehensive word list from EntityRecognizer protocol
    static func isCommonWord(_ word: String) -> Bool {
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
            "wife", "husband", "partner", "friend", "family", "whanau",
            // Days and months (prevent false positives)
            "january", "february", "march", "april", "may", "june", "july", "august",
            "september", "october", "november", "december",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            // Additional common words
            "new", "now", "old", "see", "way", "get", "let", "put", "say", "too", "use",
            "very", "well", "more", "some", "than", "then", "only", "come", "could"
        ]

        return commonWords.contains(word.lowercased())
    }

    // MARK: - Clinical Term Filtering

    /// Check if a word is a clinical abbreviation or term to exclude
    /// These are common in psychology/mental health notes and cause false positives
    static func isClinicalTerm(_ word: String) -> Bool {
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

    // MARK: - Abbreviation Filtering

    /// Check if a string is a common abbreviation (ordinals, tech terms, etc.)
    /// Used to filter false positives from identifier detection
    static func isCommonAbbreviation(_ text: String) -> Bool {
        let commonPatterns: Set<String> = [
            // Ordinals
            "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
            "11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th", "20th",
            "21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th", "30th", "31st",
            // Common tech/media abbreviations with numbers
            "covid19", "covid-19", "h1n1", "mp3", "mp4", "a4", "b12", "c19",
            "3d", "4k", "5g", "wifi", "id3"
        ]
        return commonPatterns.contains(text.lowercased())
    }

    // MARK: - Combined Filtering

    /// Check if a word should be excluded from entity detection
    /// Combines common word and clinical term checks
    static func shouldExclude(_ word: String) -> Bool {
        return isCommonWord(word) || isClinicalTerm(word)
    }
}
