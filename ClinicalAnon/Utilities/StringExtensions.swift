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
}
