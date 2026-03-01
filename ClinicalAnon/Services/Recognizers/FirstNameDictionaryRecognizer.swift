//
//  FirstNameDictionaryRecognizer.swift
//  ClinicalAnon
//
//  Purpose: Catches names missed by NER models using a 164K first name dictionary
//  Data source: names.io (Apache 2.0) — https://github.com/Debdut/names.io
//

import Foundation

// MARK: - First Name Dictionary Recognizer

/// Recognizes first names by dictionary lookup against a comprehensive 164K name dataset.
/// Acts as a safety net for uncommon names (e.g., "Hamish") that NER models miss.
/// Only matches capitalized words to avoid false positives on common words that are also names.
class FirstNameDictionaryRecognizer: EntityRecognizer {

    // MARK: - Properties

    /// Lazy-loaded set of lowercase first names from bundled dictionary
    private static let firstNames: Set<String> = {
        guard let url = Bundle.main.url(forResource: "first_names", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            print("⚠️ FirstNameDictionaryRecognizer: Could not load first_names.txt")
            return []
        }
        // File is one lowercase name per line
        let names = contents.components(separatedBy: .newlines)
            .filter { $0.count >= 3 }  // Skip very short names (high false positive risk)
        return Set(names)
    }()

    /// Minimum name length to match (avoids false positives on short words)
    private let minNameLength = 3

    // MARK: - Entity Recognition

    func recognize(in text: String) -> [Entity] {
        guard !Self.firstNames.isEmpty else { return [] }

        var entities: [Entity] = []
        let nsText = text as NSString

        // Match capitalized words (first letter uppercase, rest lowercase, 3+ chars)
        // This avoids matching ALL-CAPS headers, acronyms, or lowercase common words
        let pattern = "\\b([A-Z][a-z]{2,})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let searchRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: searchRange)

        // Track already-matched names to avoid duplicate entities
        var matchedNames = Set<String>()

        for match in matches {
            let matchedText = nsText.substring(with: match.range)
            let lowerText = matchedText.lowercased()

            // Skip if already matched this name
            guard !matchedNames.contains(lowerText) else { continue }

            // Skip common words and clinical terms
            guard !NERUtilities.shouldExclude(matchedText) else { continue }

            // Skip user-excluded names
            guard !isUserExcluded(matchedText) else { continue }

            // Check against dictionary
            guard Self.firstNames.contains(lowerText) else { continue }

            matchedNames.insert(lowerText)

            // Find ALL occurrences of this name in the text (case-insensitive word boundary)
            let namePattern = "\\b\(NSRegularExpression.escapedPattern(for: matchedText))\\b"
            guard let nameRegex = try? NSRegularExpression(pattern: namePattern, options: .caseInsensitive) else {
                continue
            }

            let nameMatches = nameRegex.matches(in: text, range: searchRange)
            var positions: [[Int]] = []
            for nameMatch in nameMatches {
                positions.append([nameMatch.range.location, nameMatch.range.location + nameMatch.range.length])
            }

            guard !positions.isEmpty else { continue }

            entities.append(Entity(
                originalText: matchedText,
                replacementCode: "",
                type: .personOther,
                positions: positions,
                confidence: 0.80
            ))
        }

        return entities
    }
}
