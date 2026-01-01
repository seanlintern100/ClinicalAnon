//
//  HighlightCacheManager.swift
//  Redactor
//
//  Purpose: Manages AttributedString caching for highlighted text display
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Highlight Cache Manager

/// Manages cached AttributedStrings for original, redacted, and restored text
@MainActor
class HighlightCacheManager: ObservableObject {

    // MARK: - Cached AttributedStrings

    @Published private(set) var cachedOriginalAttributed: AttributedString?
    @Published private(set) var cachedRedactedAttributed: AttributedString?
    @Published private(set) var cachedRestoredAttributed: AttributedString?

    // Store entities for restored text rebuilding
    private var storedAllEntities: [Entity] = []

    // MARK: - Public Methods

    /// Rebuild all highlight caches
    func rebuildAllCaches(
        originalText: String?,
        allEntities: [Entity],
        activeEntities: [Entity],
        excludedIds: Set<UUID>,
        redactedText: String,
        restoredText: String?
    ) {
        storedAllEntities = allEntities

        if let original = originalText {
            cachedOriginalAttributed = buildOriginalAttributed(
                original,
                allEntities: allEntities,
                excludedIds: excludedIds
            )
        } else {
            cachedOriginalAttributed = nil
        }

        cachedRedactedAttributed = buildRedactedAttributed(
            redactedText,
            activeEntities: activeEntities
        )

        if let restored = restoredText, !restored.isEmpty {
            cachedRestoredAttributed = buildRestoredAttributed(
                restored,
                allEntities: allEntities
            )
        }
    }

    /// Rebuild only the restored text cache
    func rebuildRestoredCache(restoredText: String) {
        cachedRestoredAttributed = buildRestoredAttributed(
            restoredText,
            allEntities: storedAllEntities
        )
    }

    /// Clear all caches
    func clearAll() {
        cachedOriginalAttributed = nil
        cachedRedactedAttributed = nil
        cachedRestoredAttributed = nil
        storedAllEntities = []
    }

    // MARK: - Private Build Methods

    private func buildOriginalAttributed(
        _ text: String,
        allEntities: [Entity],
        excludedIds: Set<UUID>
    ) -> AttributedString {
        // Use NSMutableAttributedString for UTF-16 position consistency
        let nsText = text as NSString
        let mutableAttrString = NSMutableAttributedString(string: text)

        // Set base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(DesignSystem.Colors.textPrimary)
        ]
        mutableAttrString.setAttributes(baseAttributes, range: NSRange(location: 0, length: nsText.length))

        for entity in allEntities {
            let isExcluded = excludedIds.contains(entity.id)
            let bgColor = isExcluded
                ? NSColor.gray.withAlphaComponent(0.3)
                : NSColor(entity.type.highlightColor)
            let fgColor = isExcluded
                ? NSColor(DesignSystem.Colors.textSecondary)
                : NSColor(DesignSystem.Colors.textPrimary)

            for position in entity.positions {
                guard position.count >= 2 else { continue }
                let start = position[0]
                let end = position[1]

                // Validate against NSString length (UTF-16)
                guard start >= 0 && end <= nsText.length && start < end else { continue }

                let range = NSRange(location: start, length: end - start)
                mutableAttrString.addAttribute(.backgroundColor, value: bgColor, range: range)
                mutableAttrString.addAttribute(.foregroundColor, value: fgColor, range: range)
            }
        }

        // Convert to AttributedString
        return AttributedString(mutableAttrString)
    }

    private func buildRedactedAttributed(
        _ text: String,
        activeEntities: [Entity]
    ) -> AttributedString {
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        for entity in activeEntities {
            let code = entity.replacementCode
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex
                if let range = attributedString[searchRange].range(of: code) {
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return attributedString
    }

    private func buildRestoredAttributed(
        _ text: String,
        allEntities: [Entity]
    ) -> AttributedString {
        var attributedString = MarkdownParser.parseToAttributedString(text, baseFont: .systemFont(ofSize: 14))
        attributedString.foregroundColor = NSColor(DesignSystem.Colors.textPrimary)

        for entity in allEntities {
            let originalText = entity.originalText
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex
                if let range = attributedString[searchRange].range(of: originalText, options: [.caseInsensitive]) {
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor(DesignSystem.Colors.textPrimary)
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return attributedString
    }
}
