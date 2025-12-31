//
//  DeepScanRecognizer.swift
//  Redactor
//
//  Purpose: Aggressive NER for catching foreign names and hard-to-capture terms
//  Organization: 3 Big Things
//

import Foundation
import NaturalLanguage

// MARK: - Deep Scan Recognizer

/// Aggressive entity recognizer that trades precision for recall
/// Designed to catch foreign names and terms that standard NER misses
class DeepScanRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Common name particles (lowercase words that appear in names)
    private let nameParticles: Set<String> = [
        "de", "van", "von", "der", "den", "la", "le", "du", "da", "dos", "das",
        "del", "della", "di", "el", "al", "bin", "ibn", "ben", "mac", "mc", "o'",
        "te", "ter", "ten", "het", "op", "tot", "zur", "zum", "af"
    ]

    /// Relationship/context trigger words for name detection
    private let relationshipTriggers: Set<String> = [
        "cousin", "aunt", "uncle", "nephew", "niece", "friend", "colleague",
        "neighbor", "neighbour", "partner", "boyfriend", "girlfriend",
        "fiancee", "fiance", "mother", "father", "brother", "sister",
        "grandmother", "grandfather", "grandma", "grandpa", "son", "daughter",
        "wife", "husband", "stepmother", "stepfather", "stepsister", "stepbrother",
        "mr", "mrs", "ms", "miss", "dr", "prof", "pastor", "reverend",
        "coach", "teacher", "boss", "manager", "supervisor"
    ]

    /// Common English words to exclude (top ~500 most common)
    private lazy var commonEnglishWords: Set<String> = {
        return [
            // Articles & determiners
            "the", "a", "an", "this", "that", "these", "those", "my", "your",
            "his", "her", "its", "our", "their", "some", "any", "no", "every",
            // Pronouns
            "i", "you", "he", "she", "it", "we", "they", "me", "him", "them",
            "us", "who", "what", "which", "whom", "whose", "myself", "yourself",
            // Prepositions
            "in", "on", "at", "to", "for", "from", "with", "by", "about", "into",
            "through", "during", "before", "after", "above", "below", "between",
            "under", "over", "out", "up", "down", "off", "away", "around",
            // Conjunctions
            "and", "but", "or", "nor", "so", "yet", "because", "although",
            "while", "if", "when", "where", "unless", "since", "until",
            // Common verbs
            "is", "are", "was", "were", "be", "been", "being", "have", "has",
            "had", "do", "does", "did", "will", "would", "could", "should",
            "may", "might", "must", "can", "shall", "get", "got", "go", "going",
            "went", "come", "came", "take", "took", "make", "made", "see", "saw",
            "know", "knew", "think", "thought", "want", "need", "feel", "felt",
            "give", "gave", "tell", "told", "say", "said", "find", "found",
            "put", "keep", "kept", "let", "begin", "began", "seem", "help",
            "show", "showed", "hear", "heard", "play", "run", "ran", "move",
            "live", "believe", "hold", "held", "bring", "brought", "happen",
            "write", "wrote", "provide", "sit", "sat", "stand", "stood", "lose",
            "lost", "pay", "paid", "meet", "met", "include", "continue", "set",
            "learn", "change", "lead", "led", "understand", "understood", "watch",
            "follow", "stop", "create", "speak", "spoke", "read", "spend", "spent",
            "grow", "grew", "open", "walk", "win", "won", "offer", "remember",
            "love", "consider", "appear", "buy", "bought", "wait", "serve", "die",
            "send", "sent", "expect", "build", "built", "stay", "fall", "fell",
            "cut", "reach", "kill", "remain", "suggest", "raise", "pass", "sell",
            "sold", "require", "report", "decide", "pull",
            // Common adjectives
            "good", "new", "first", "last", "long", "great", "little", "own",
            "other", "old", "right", "big", "high", "different", "small", "large",
            "next", "early", "young", "important", "few", "public", "bad", "same",
            "able", "best", "better", "sure", "free", "full", "clear", "true",
            "whole", "real", "open", "late", "hard", "low", "easy", "past",
            "possible", "private", "strong", "poor", "happy", "serious", "ready",
            "simple", "left", "physical", "general", "personal", "single", "likely",
            // Common nouns (non-names)
            "time", "year", "people", "way", "day", "man", "thing", "woman",
            "life", "child", "world", "school", "state", "family", "student",
            "group", "country", "problem", "hand", "part", "place", "case",
            "week", "company", "system", "program", "question", "work", "government",
            "number", "night", "point", "home", "water", "room", "mother", "area",
            "money", "story", "fact", "month", "lot", "right", "study", "book",
            "eye", "job", "word", "business", "issue", "side", "kind", "head",
            "house", "service", "friend", "father", "power", "hour", "game",
            "line", "end", "member", "law", "car", "city", "community", "name",
            "president", "team", "minute", "idea", "kid", "body", "information",
            "back", "parent", "face", "others", "level", "office", "door", "health",
            "person", "art", "war", "history", "party", "result", "change", "morning",
            "reason", "research", "girl", "guy", "moment", "air", "teacher", "force",
            "education", "food", "patient", "treatment", "therapy", "session",
            "client", "report", "note", "meeting", "doctor", "hospital", "clinic",
            // Common adverbs
            "not", "also", "very", "often", "however", "too", "usually", "really",
            "early", "never", "always", "sometimes", "together", "likely", "simply",
            "generally", "instead", "actually", "already", "ever", "well", "then",
            "now", "here", "there", "today", "still", "just", "only", "even",
            "back", "much", "more", "most", "less", "again", "away", "once",
            // Clinical/medical terms (keep detecting these as they're not PII)
            "assessment", "intervention", "diagnosis", "symptoms", "medication",
            "progress", "goals", "plan", "history", "background", "summary",
            "recommendations", "actions", "notes", "comments", "current",
            // Days/months
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
            "sunday", "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
            // Professional titles
            "psychologist", "therapist", "physician", "psychiatrist", "nurse",
            "consultant", "specialist", "clinician", "practitioner", "counselor",
            "counsellor", "occupational", "physiotherapist", "neuropsychologist",
            "registered", "senior", "assistant", "associate", "director",
            // Clinical/medical terms (expanded)
            "report", "service", "services", "programme",
            "rehabilitation", "medical", "clinical", "psychology", "neuropsychological",
            "concussion", "independence", "wellbeing", "wellness", "behaviour",
            "behavior", "pain", "management", "support", "central", "specialist",
            "medicine", "injury", "injuries", "accident", "trauma",
            // Document/admin terms
            "form", "sections", "submission", "date", "claim", "address",
            "supplier", "provider", "physical", "mental", "status", "review",
            "signature", "signed", "approved", "submitted", "received"
        ]
    }()

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []

        // 1. Unfiltered Apple NER
        entities.append(contentsOf: detectWithUnfilteredNER(text))

        // 2. Diacritic words (foreign names with accents)
        entities.append(contentsOf: detectDiacriticWords(text))

        // 3. Names after relationship triggers
        entities.append(contentsOf: detectCapitalizedAfterTriggers(text))

        // 4. Capitalized word sequences (multi-word names)
        entities.append(contentsOf: detectCapitalizedSequences(text))

        // 5. Names with particles (e.g., "Jurriaan de Groot", "van der Berg")
        entities.append(contentsOf: detectNamesWithParticles(text))

        // Merge adjacent capitalized words into single entities
        let merged = mergeAdjacentNames(entities, in: text)

        // Deduplicate within our findings
        return deduplicateFindings(merged)
    }

    // MARK: - Detection Strategy 1: Unfiltered NER

    /// Run Apple NER without common word/clinical term filters
    private func detectWithUnfilteredNER(_ text: String) -> [Entity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [Entity] = []

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            guard let tag = tag, tag == .personalName else { return true }

            let name = String(text[range])

            // Only skip user-excluded words (no common word filter!)
            guard !isUserExcluded(name) else { return true }

            // Skip very short words
            guard name.count >= 2 else { return true }

            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.distance(from: text.startIndex, to: range.upperBound)

            entities.append(Entity(
                originalText: name,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.5  // Lower confidence for deep scan
            ))

            return true
        }

        return entities
    }

    // MARK: - Detection Strategy 2: Diacritic Words

    /// Detect words containing diacritical marks (likely foreign names)
    private func detectDiacriticWords(_ text: String) -> [Entity] {
        var entities: [Entity] = []

        // Pattern: Capitalized word containing diacritics
        let diacriticPattern = "\\b[A-Z\u{00C0}-\u{017F}][a-z\u{00E0}-\u{017F}]{1,}\\b"

        guard let regex = try? NSRegularExpression(pattern: diacriticPattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let word = String(text[matchRange])

            // Must contain an actual diacritic character
            guard containsDiacritic(word) else { continue }

            // Skip user-excluded
            guard !isUserExcluded(word) else { continue }

            let start = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: matchRange.upperBound)

            entities.append(Entity(
                originalText: word,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.6  // Slightly higher - diacritics are good indicator
            ))
        }

        return entities
    }

    /// Check if word contains diacritic characters
    private func containsDiacritic(_ word: String) -> Bool {
        let diacritics = CharacterSet(charactersIn: "àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĲĳĴĵĶķĸĹĺĻļĽľĿŀŁłŃńŅņŇňŉŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž")
        return word.unicodeScalars.contains { diacritics.contains($0) }
    }

    // MARK: - Detection Strategy 3: After Relationship Triggers

    /// Detect capitalized words following relationship terms
    private func detectCapitalizedAfterTriggers(_ text: String) -> [Entity] {
        var entities: [Entity] = []

        let triggerPattern = relationshipTriggers.joined(separator: "|")
        // Match trigger + space + 1-3 capitalized words
        let pattern = "\\b(\(triggerPattern))\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+){0,2})"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            // Get the name part (capture group 2)
            guard match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let name = String(text[nameRange])

            // Skip user-excluded and common words
            guard !isUserExcluded(name) else { continue }
            guard !isCommonEnglishWord(name) else { continue }

            let start = text.distance(from: text.startIndex, to: nameRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: nameRange.upperBound)

            entities.append(Entity(
                originalText: name,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.6  // Higher confidence - clear context
            ))
        }

        return entities
    }

    // MARK: - Detection Strategy 4: Capitalized Sequences

    /// Detect sequences of 2-3 capitalized words (potential multi-word names)
    private func detectCapitalizedSequences(_ text: String) -> [Entity] {
        var entities: [Entity] = []

        // Pattern: 2-3 consecutive capitalized words
        let pattern = "\\b([A-Z][a-z]+)\\s+([A-Z][a-z]+)(?:\\s+([A-Z][a-z]+))?\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let sequence = String(text[matchRange])
            let words = sequence.components(separatedBy: " ")

            // Skip if at start of sentence
            let matchStart = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            if isAtSentenceStart(position: matchStart, in: text) {
                continue
            }

            // Skip if followed by colon (likely a heading)
            if isFollowedByColon(range: matchRange, in: text) {
                continue
            }

            // Skip if all words are common English words
            if words.allSatisfy({ isCommonEnglishWord($0) }) {
                continue
            }

            // Skip user-excluded
            guard !isUserExcluded(sequence) else { continue }

            let start = matchStart
            let end = text.distance(from: text.startIndex, to: matchRange.upperBound)

            entities.append(Entity(
                originalText: sequence,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.5
            ))
        }

        return entities
    }

    // MARK: - Detection Strategy 5: Names with Particles

    /// Detect names containing particles like "de", "van", "von"
    /// Examples: "Jurriaan de Groot", "van der Berg", "Maria del Carmen"
    private func detectNamesWithParticles(_ text: String) -> [Entity] {
        var entities: [Entity] = []

        // Build particle pattern from our list
        let particlePattern = nameParticles.joined(separator: "|")

        // Pattern: Capitalized + particle(s) + Capitalized
        // e.g., "Jurriaan de Groot", "Jan van der Berg"
        let pattern = "\\b([A-Z][a-z]+)\\s+((?:(?:\(particlePattern))\\s+)+)([A-Z][a-z]+)\\b"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let fullName = String(text[matchRange])

            // Skip user-excluded
            guard !isUserExcluded(fullName) else { continue }

            let start = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            let end = text.distance(from: text.startIndex, to: matchRange.upperBound)

            entities.append(Entity(
                originalText: fullName,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.7  // Higher confidence - clear name pattern
            ))
        }

        // Also detect: particle + Capitalized (e.g., "de Groot" without first name)
        let partialPattern = "\\b((?:\(particlePattern))\\s+)([A-Z][a-z]+)\\b"

        guard let partialRegex = try? NSRegularExpression(pattern: partialPattern, options: .caseInsensitive) else {
            return entities
        }

        let partialMatches = partialRegex.matches(in: text, range: range)

        for match in partialMatches {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let partialName = String(text[matchRange])

            // Skip user-excluded
            guard !isUserExcluded(partialName) else { continue }

            // Skip if at sentence start
            let matchStart = text.distance(from: text.startIndex, to: matchRange.lowerBound)
            if isAtSentenceStart(position: matchStart, in: text) {
                continue
            }

            let start = matchStart
            let end = text.distance(from: text.startIndex, to: matchRange.upperBound)

            entities.append(Entity(
                originalText: partialName,
                replacementCode: "",
                type: .personOther,
                positions: [[start, end]],
                confidence: 0.5
            ))
        }

        return entities
    }

    // MARK: - Adjacent Name Merging

    /// Merge adjacent capitalized word entities into single multi-word names
    /// Example: "Janet" + "Leathem" -> "Janet Leathem"
    private func mergeAdjacentNames(_ entities: [Entity], in text: String) -> [Entity] {
        guard !entities.isEmpty else { return entities }

        // Sort by position
        let sorted = entities.sorted { entity1, entity2 in
            guard let pos1 = entity1.positions.first?.first,
                  let pos2 = entity2.positions.first?.first else {
                return false
            }
            return pos1 < pos2
        }

        var result: [Entity] = []
        var i = 0

        while i < sorted.count {
            var currentEntity = sorted[i]

            // Try to merge with following adjacent entities
            while i + 1 < sorted.count {
                let nextEntity = sorted[i + 1]

                // Check if they're adjacent (separated by single space)
                guard let currentEnd = currentEntity.positions.first?.last,
                      let nextStart = nextEntity.positions.first?.first,
                      let nextEnd = nextEntity.positions.first?.last else {
                    break
                }

                // Check if there's exactly one space between them
                let gap = nextStart - currentEnd
                if gap == 1 {
                    // Check the character between is a space
                    let gapStart = text.index(text.startIndex, offsetBy: currentEnd)
                    let gapEnd = text.index(text.startIndex, offsetBy: nextStart)
                    let gapChar = String(text[gapStart..<gapEnd])

                    if gapChar == " " {
                        // Both words should be capitalized
                        let currentWord = currentEntity.originalText
                        let nextWord = nextEntity.originalText

                        if startsWithCapital(currentWord) && startsWithCapital(nextWord) {
                            // Merge them
                            let mergedText = currentWord + " " + nextWord
                            let mergedStart = currentEntity.positions.first?.first ?? 0
                            currentEntity = Entity(
                                originalText: mergedText,
                                replacementCode: "",
                                type: .personOther,
                                positions: [[mergedStart, nextEnd]],
                                confidence: 0.6  // Higher confidence for multi-word names
                            )
                            i += 1
                            continue
                        }
                    }
                }
                break
            }

            result.append(currentEntity)
            i += 1
        }

        return result
    }

    /// Check if word starts with a capital letter
    private func startsWithCapital(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return first.isUppercase
    }

    // MARK: - Helper Methods

    /// Check if word is a common English word
    private func isCommonEnglishWord(_ word: String) -> Bool {
        return commonEnglishWords.contains(word.lowercased())
    }

    /// Check if position is at the start of a sentence
    private func isAtSentenceStart(position: Int, in text: String) -> Bool {
        guard position > 0 else { return true }

        let idx = text.index(text.startIndex, offsetBy: position - 1)
        let prevChar = text[idx]

        // Check for sentence-ending punctuation or newline before this position
        if prevChar == "." || prevChar == "!" || prevChar == "?" || prevChar == "\n" {
            return true
        }

        // Check for punctuation followed by space
        if position > 1 {
            let prevIdx = text.index(text.startIndex, offsetBy: position - 2)
            let prevPrevChar = text[prevIdx]
            if (prevPrevChar == "." || prevPrevChar == "!" || prevPrevChar == "?") && prevChar == " " {
                return true
            }
        }

        return false
    }

    /// Check if match is followed by a colon (likely a heading)
    private func isFollowedByColon(range: Range<String.Index>, in text: String) -> Bool {
        guard range.upperBound < text.endIndex else { return false }

        var idx = range.upperBound
        // Skip whitespace
        while idx < text.endIndex && text[idx].isWhitespace {
            idx = text.index(after: idx)
        }

        return idx < text.endIndex && text[idx] == ":"
    }

    /// Deduplicate entities by text (case-insensitive)
    private func deduplicateFindings(_ entities: [Entity]) -> [Entity] {
        var seen = Set<String>()
        var result: [Entity] = []

        for entity in entities {
            let key = entity.originalText.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(entity)
            }
        }

        return result
    }
}
