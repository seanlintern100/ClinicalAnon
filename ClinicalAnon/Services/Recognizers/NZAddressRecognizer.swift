//
//  NZAddressRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Detects NZ addresses, suburbs, cities, and place names
//  Data: nz_places.txt — 1,498 NZ place names from LINZ Gazetteer + Stats NZ
//  Organization: 3 Big Things
//

import Foundation

// MARK: - NZ Address Recognizer

/// Recognizes New Zealand addresses, suburbs, cities, and place names.
/// Combines regex patterns (street addresses, hospitals, DHBs) with a
/// dictionary of ~1,500 NZ place names loaded from nz_places.txt.
class NZAddressRecognizer: EntityRecognizer {

    // MARK: - Place Name Dictionary

    /// Lazy-loaded set of NZ place names, keyed by lowercase for lookup.
    /// Values are the original-case names for display.
    private static let placeNames: [String: String] = {
        guard let url = Bundle.main.url(forResource: "nz_places", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            print("⚠️ NZAddressRecognizer: Could not load nz_places.txt")
            return [:]
        }
        var dict: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            dict[trimmed.lowercased()] = trimmed
        }
        #if DEBUG
        print("📍 NZAddressRecognizer: Loaded \(dict.count) NZ place names")
        #endif
        return dict
    }()

    /// Multi-word place names need separate handling — build regex for them
    private static let multiWordPlaceRegex: NSRegularExpression? = {
        let multiWordNames = placeNames.values
            .filter { $0.contains(" ") }
            .sorted { $0.count > $1.count } // Longest first for greedy matching
            .map { NSRegularExpression.escapedPattern(for: $0) }
        guard !multiWordNames.isEmpty else { return nil }
        let pattern = "\\b(?:" + multiWordNames.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    /// Single-word place names as a set for fast lookup
    private static let singleWordPlaces: Set<String> = {
        Set(placeNames.keys.filter { !$0.contains(" ") })
    }()

    // MARK: - Regex Patterns

    private static let streetAddressRegex: NSRegularExpression? = {
        let pattern = "\\d+\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+(?:Road|Street|Terrace|Avenue|Drive|Lane|Place|Crescent|Way|Grove|Close|Court)\\b"
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static let hospitalRegex: NSRegularExpression? = {
        let pattern = "\\b(?:Auckland|Middlemore|North Shore|Waitakere|Starship|Greenlane|Wellington|Hutt|Christchurch|Dunedin|Waikato|Tauranga|Rotorua|Palmerston North|Hawke'?s Bay|Southland|Nelson|Taranaki Base|Whangarei|Thames|Kenepuru|Burwood)\\s+Hospital\\b"
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static let dhbRegex: NSRegularExpression? = {
        let pattern = "\\b(?:Auckland|Waitemata|Counties Manukau|Canterbury|Southern|Capital & Coast|Hutt Valley|Waikato|Bay of Plenty|Lakes|Taranaki|Whanganui|MidCentral|Hawke'?s Bay|Nelson Marlborough|South Canterbury|West Coast|Northland)\\s+(?:DHB|District Health Board|Health|Clinic)\\b"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        var entities: [Entity] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1. Street addresses (high confidence)
        if let regex = Self.streetAddressRegex {
            for match in regex.matches(in: text, range: fullRange) {
                let matched = nsText.substring(with: match.range)
                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "",
                    type: .location,
                    positions: [[match.range.location, match.range.location + match.range.length]],
                    confidence: 0.9
                ))
            }
        }

        // 2. Hospital names (high confidence)
        if let regex = Self.hospitalRegex {
            for match in regex.matches(in: text, range: fullRange) {
                let matched = nsText.substring(with: match.range)
                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "",
                    type: .location,
                    positions: [[match.range.location, match.range.location + match.range.length]],
                    confidence: 0.95
                ))
            }
        }

        // 3. DHB/Clinic references (as organizations)
        if let regex = Self.dhbRegex {
            for match in regex.matches(in: text, range: fullRange) {
                let matched = nsText.substring(with: match.range)
                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "",
                    type: .organization,
                    positions: [[match.range.location, match.range.location + match.range.length]],
                    confidence: 0.9
                ))
            }
        }

        // 4. Multi-word place names from dictionary (e.g., "Palmerston North", "New Plymouth")
        if let regex = Self.multiWordPlaceRegex {
            for match in regex.matches(in: text, range: fullRange) {
                let matched = nsText.substring(with: match.range)
                guard !isUserExcluded(matched) else { continue }
                entities.append(Entity(
                    originalText: matched,
                    replacementCode: "",
                    type: .location,
                    positions: [[match.range.location, match.range.location + match.range.length]],
                    confidence: 0.88
                ))
            }
        }

        // 5. Single-word place names from dictionary
        // Match capitalized words and check against place name set
        let wordPattern = "\\b([A-Z][a-zā-ū]{2,})\\b"
        if let wordRegex = try? NSRegularExpression(pattern: wordPattern) {
            var matchedPlaces = Set<String>()
            let matches = wordRegex.matches(in: text, range: fullRange)

            for match in matches {
                let word = nsText.substring(with: match.range)
                let lower = word.lowercased()

                guard !matchedPlaces.contains(lower) else { continue }
                guard Self.singleWordPlaces.contains(lower) else { continue }
                guard !NERUtilities.shouldExclude(word) else { continue }
                guard !isUserExcluded(word) else { continue }

                matchedPlaces.insert(lower)

                // Find ALL occurrences of this place name
                let placePattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
                guard let placeRegex = try? NSRegularExpression(pattern: placePattern, options: .caseInsensitive) else {
                    continue
                }

                var positions: [[Int]] = []
                for placeMatch in placeRegex.matches(in: text, range: fullRange) {
                    positions.append([placeMatch.range.location, placeMatch.range.location + placeMatch.range.length])
                }

                guard !positions.isEmpty else { continue }

                entities.append(Entity(
                    originalText: word,
                    replacementCode: "",
                    type: .location,
                    positions: positions,
                    confidence: 0.85
                ))
            }
        }

        return entities
    }
}
