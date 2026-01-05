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
        replacementPositions: [(range: NSRange, entityType: EntityType)],
        restoredText: String?
    ) {
        storedAllEntities = allEntities

        // Build original attributed string
        if let original = originalText {
            cachedOriginalAttributed = buildOriginalAttributed(
                original,
                allEntities: allEntities,
                excludedIds: excludedIds
            )
        } else {
            cachedOriginalAttributed = nil
        }

        // Build redacted attributed string using pre-calculated positions (O(m) vs O(n*m))
        cachedRedactedAttributed = buildRedactedAttributed(
            redactedText,
            replacementPositions: replacementPositions
        )

        // Build restored attributed string
        if let restored = restoredText, !restored.isEmpty {
            cachedRestoredAttributed = buildRestoredAttributed(restored, allEntities: allEntities)
        } else {
            cachedRestoredAttributed = nil
        }
    }

    /// Rebuild only the restored text cache
    func rebuildRestoredCache(restoredText: String) {
        cachedRestoredAttributed = buildRestoredAttributed(restoredText, allEntities: storedAllEntities)
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
            .foregroundColor: NSColor.labelColor
        ]
        mutableAttrString.setAttributes(baseAttributes, range: NSRange(location: 0, length: nsText.length))

        for entity in allEntities {
            let isExcluded = excludedIds.contains(entity.id)
            let bgColor = isExcluded
                ? NSColor.gray.withAlphaComponent(0.3)
                : NSColor(entity.type.highlightColor)
            let fgColor = isExcluded
                ? NSColor.secondaryLabelColor
                : NSColor.labelColor

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
        replacementPositions: [(range: NSRange, entityType: EntityType)]
    ) -> AttributedString {
        // Use NSMutableAttributedString for efficient attribute application at known positions
        let mutableAttrString = NSMutableAttributedString(string: text)
        let nsText = text as NSString

        // Set base attributes
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        mutableAttrString.setAttributes(baseAttributes, range: NSRange(location: 0, length: nsText.length))

        // Apply highlighting at pre-calculated positions (O(m) instead of O(n*m) searches)
        for (range, entityType) in replacementPositions {
            // Validate range is within bounds
            guard range.location >= 0 && range.location + range.length <= nsText.length else { continue }
            mutableAttrString.addAttribute(.backgroundColor, value: NSColor(entityType.highlightColor), range: range)
        }

        return AttributedString(mutableAttrString)
    }

    private func buildRestoredAttributed(
        _ text: String,
        allEntities: [Entity]
    ) -> AttributedString {
        // Start with markdown-parsed NSAttributedString for safe UTF-16 index handling
        let nsAttrString = MarkdownParser.parseToNSAttributedString(text, baseFont: .systemFont(ofSize: 14))
        let mutableAttrString = NSMutableAttributedString(attributedString: nsAttrString)
        let nsText = mutableAttrString.string as NSString

        // Set base foreground color
        mutableAttrString.addAttribute(
            .foregroundColor,
            value: NSColor.labelColor,
            range: NSRange(location: 0, length: nsText.length)
        )

        // Find and highlight each entity's original text
        for entity in allEntities {
            let originalText = entity.originalText
            var searchStart = 0

            while searchStart < nsText.length {
                let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
                let foundRange = nsText.range(of: originalText, options: [.caseInsensitive], range: searchRange)

                if foundRange.location == NSNotFound {
                    break
                }

                mutableAttrString.addAttribute(.backgroundColor, value: NSColor(entity.type.highlightColor), range: foundRange)
                mutableAttrString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: foundRange)

                searchStart = foundRange.location + foundRange.length
            }
        }

        return AttributedString(mutableAttrString)
    }
}
