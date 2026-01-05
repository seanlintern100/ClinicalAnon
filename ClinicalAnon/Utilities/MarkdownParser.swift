import Foundation
import AppKit

/// Utility for parsing Markdown text and converting to formatted output
struct MarkdownParser {

    // MARK: - Public Methods

    /// Parse Markdown text to AttributedString for SwiftUI display
    static func parseToAttributedString(_ markdown: String, baseFont: NSFont = .systemFont(ofSize: 14)) -> AttributedString {
        let nsAttributedString = parseToNSAttributedString(markdown, baseFont: baseFont)
        return AttributedString(nsAttributedString)
    }

    /// Parse Markdown text to NSAttributedString
    static func parseToNSAttributedString(_ markdown: String, baseFont: NSFont = .systemFont(ofSize: 14)) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let processedLine = processLine(line, baseFont: baseFont)
            result.append(processedLine)

            // Add newline between lines (except last)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    /// Convert Markdown to RTF data for clipboard (Word-compatible)
    static func parseToRTFData(_ markdown: String, baseFont: NSFont = .systemFont(ofSize: 14)) -> Data? {
        let attributedString = parseToNSAttributedString(markdown, baseFont: baseFont)
        let range = NSRange(location: 0, length: attributedString.length)

        return try? attributedString.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: - Private Methods

    private static func processLine(_ line: String, baseFont: NSFont) -> NSAttributedString {
        var processedLine = line
        var isHeader = false
        var headerLevel = 0

        // Check for headers
        if let headerMatch = processedLine.range(of: "^#{1,6}\\s+", options: .regularExpression) {
            let headerMarker = String(processedLine[headerMatch])
            headerLevel = headerMarker.filter { $0 == "#" }.count
            processedLine = String(processedLine[headerMatch.upperBound...])
            isHeader = true
        }

        // Process inline formatting
        let result = processInlineFormatting(processedLine, baseFont: baseFont, isHeader: isHeader, headerLevel: headerLevel)

        return result
    }

    private static func processInlineFormatting(_ text: String, baseFont: NSFont, isHeader: Bool, headerLevel: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentIndex = text.startIndex

        // Determine base attributes
        var baseAttributes: [NSAttributedString.Key: Any] = [:]

        if isHeader {
            // Scale headers relative to base font size for proportional appearance
            let headerMultipliers: [Int: CGFloat] = [1: 1.4, 2: 1.25, 3: 1.1, 4: 1.0, 5: 0.95, 6: 0.9]
            let multiplier = headerMultipliers[headerLevel] ?? 1.0
            let size = baseFont.pointSize * multiplier
            baseAttributes[.font] = NSFont.boldSystemFont(ofSize: size)
        } else {
            baseAttributes[.font] = baseFont
        }

        while currentIndex < text.endIndex {
            // Look for bold+italic (***text*** or ___text___)
            if let match = findPattern(in: text, from: currentIndex, pattern: "(\\*{3}|_{3})(.+?)\\1") {
                // Add text before match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(text[currentIndex..<match.range.lowerBound])
                    result.append(NSAttributedString(string: beforeText, attributes: baseAttributes))
                }

                // Add bold+italic text
                var attrs = baseAttributes
                let currentFont = attrs[.font] as? NSFont ?? baseFont
                attrs[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: [.boldFontMask, .italicFontMask])
                result.append(NSAttributedString(string: match.content, attributes: attrs))

                currentIndex = match.range.upperBound
                continue
            }

            // Look for bold (**text** or __text__)
            if let match = findPattern(in: text, from: currentIndex, pattern: "(\\*{2}|_{2})(.+?)\\1") {
                // Add text before match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(text[currentIndex..<match.range.lowerBound])
                    result.append(NSAttributedString(string: beforeText, attributes: baseAttributes))
                }

                // Add bold text
                var attrs = baseAttributes
                let currentFont = attrs[.font] as? NSFont ?? baseFont
                attrs[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .boldFontMask)
                result.append(NSAttributedString(string: match.content, attributes: attrs))

                currentIndex = match.range.upperBound
                continue
            }

            // Look for italic (*text* or _text_) - be careful not to match ** or __
            // Also skip if content looks like a code identifier (contains more underscores)
            if let match = findPattern(in: text, from: currentIndex, pattern: "(?<![\\*_])([\\*_])(?![\\*_])(.+?)(?<![\\*_])\\1(?![\\*_])") {
                // Skip italic formatting if content contains underscores (likely a code/placeholder like PERSON_A)
                let isCodeIdentifier = match.content.contains("_")

                // Also skip if we're inside square brackets (placeholder like [PERSON_A_FIRST])
                let textBefore = String(text[text.startIndex..<match.range.lowerBound])
                let lastOpenBracket = textBefore.lastIndex(of: "[")
                let lastCloseBracket = textBefore.lastIndex(of: "]")
                let insideBrackets = lastOpenBracket != nil && (lastCloseBracket == nil || lastOpenBracket! > lastCloseBracket!)

                if isCodeIdentifier || insideBrackets {
                    // Don't apply italic formatting - treat as literal text
                    // Move forward by one character to continue parsing
                    let char = String(text[currentIndex])
                    result.append(NSAttributedString(string: char, attributes: baseAttributes))
                    currentIndex = text.index(after: currentIndex)
                    continue
                }

                // Add text before match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(text[currentIndex..<match.range.lowerBound])
                    result.append(NSAttributedString(string: beforeText, attributes: baseAttributes))
                }

                // Add italic text
                var attrs = baseAttributes
                let currentFont = attrs[.font] as? NSFont ?? baseFont
                attrs[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                result.append(NSAttributedString(string: match.content, attributes: attrs))

                currentIndex = match.range.upperBound
                continue
            }

            // Look for strikethrough (~~text~~)
            if let match = findPattern(in: text, from: currentIndex, pattern: "~~(.+?)~~") {
                // Add text before match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(text[currentIndex..<match.range.lowerBound])
                    result.append(NSAttributedString(string: beforeText, attributes: baseAttributes))
                }

                // Add strikethrough text
                var attrs = baseAttributes
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(NSAttributedString(string: match.content, attributes: attrs))

                currentIndex = match.range.upperBound
                continue
            }

            // Look for inline code (`code`)
            if let match = findPattern(in: text, from: currentIndex, pattern: "`([^`]+)`") {
                // Add text before match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(text[currentIndex..<match.range.lowerBound])
                    result.append(NSAttributedString(string: beforeText, attributes: baseAttributes))
                }

                // Add code text with monospace font
                var attrs = baseAttributes
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                attrs[.backgroundColor] = NSColor.gray.withAlphaComponent(0.2)
                result.append(NSAttributedString(string: match.content, attributes: attrs))

                currentIndex = match.range.upperBound
                continue
            }

            // No match found, add remaining text
            let remainingText = String(text[currentIndex...])
            result.append(NSAttributedString(string: remainingText, attributes: baseAttributes))
            break
        }

        return result
    }

    private struct PatternMatch {
        let range: Range<String.Index>
        let content: String
    }

    private static func findPattern(in text: String, from startIndex: String.Index, pattern: String) -> PatternMatch? {
        let searchRange = startIndex..<text.endIndex
        let searchText = String(text[searchRange])

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(searchText.startIndex..<searchText.endIndex, in: searchText)
        guard let match = regex.firstMatch(in: searchText, options: [], range: nsRange) else {
            return nil
        }

        // Get the content (last capture group)
        let contentGroupIndex = regex.numberOfCaptureGroups
        guard let contentRange = Range(match.range(at: contentGroupIndex), in: searchText) else {
            return nil
        }
        let content = String(searchText[contentRange])

        // Calculate the full match range in original string
        guard let matchRange = Range(match.range, in: searchText) else {
            return nil
        }

        let fullRangeLower = text.index(startIndex, offsetBy: searchText.distance(from: searchText.startIndex, to: matchRange.lowerBound))
        let fullRangeUpper = text.index(startIndex, offsetBy: searchText.distance(from: searchText.startIndex, to: matchRange.upperBound))

        return PatternMatch(range: fullRangeLower..<fullRangeUpper, content: content)
    }
}
