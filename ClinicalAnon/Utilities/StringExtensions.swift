//
//  StringExtensions.swift
//  Redactor
//
//  Purpose: Shared String utilities
//  Organization: 3 Big Things
//

import Foundation

// MARK: - String Extensions

extension String {

    /// Create regex from pattern, returns nil if invalid
    func asRegex(options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: self, options: options)
    }

    /// Count occurrences of a substring
    /// - Parameter substring: The substring to count
    /// - Returns: Number of occurrences
    func occurrences(of substring: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        return components(separatedBy: substring).count - 1
    }

    /// Word count (splits on whitespace and newlines)
    var wordCount: Int {
        let words = self.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }

    /// Character count excluding whitespace
    var nonWhitespaceCount: Int {
        return self.filter { !$0.isWhitespace }.count
    }

    /// Levenshtein edit distance (two-row optimised, O(min(n,m)) memory)
    func levenshteinDistance(to other: String) -> Int {
        let s = Array(self)
        let t = Array(other)
        let n = s.count
        let m = t.count

        if n == 0 { return m }
        if m == 0 { return n }

        // Keep shorter string as column to minimise memory
        if n > m { return other.levenshteinDistance(to: self) }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for j in 1...m {
            curr[0] = j
            for i in 1...n {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[i] = Swift.min(
                    curr[i - 1] + 1,
                    Swift.min(
                        prev[i] + 1,
                        prev[i - 1] + cost
                    )
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
