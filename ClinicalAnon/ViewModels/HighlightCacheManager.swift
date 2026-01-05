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
/// Uses background thread processing for large documents
@MainActor
class HighlightCacheManager: ObservableObject {

    // MARK: - Cached AttributedStrings

    @Published private(set) var cachedOriginalAttributed: AttributedString?
    @Published private(set) var cachedRedactedAttributed: AttributedString?
    @Published private(set) var cachedRestoredAttributed: AttributedString?

    /// Indicates if a background build is in progress
    @Published private(set) var isBuilding: Bool = false

    // Store entities for restored text rebuilding
    private var storedAllEntities: [Entity] = []

    // Cancellable build task
    private var buildTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Rebuild all highlight caches (runs on background thread)
    func rebuildAllCaches(
        originalText: String?,
        allEntities: [Entity],
        activeEntities: [Entity],
        excludedIds: Set<UUID>,
        redactedText: String,
        restoredText: String?
    ) {
        // Cancel any in-progress build
        buildTask?.cancel()

        storedAllEntities = allEntities
        isBuilding = true

        // Capture values for background thread (avoid capturing self)
        let original = originalText
        let entities = allEntities
        let active = activeEntities
        let excluded = excludedIds
        let redacted = redactedText
        let restored = restoredText

        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            // Build on background thread
            let originalAttr: AttributedString? = original.map { text in
                Self.buildOriginalAttributedBackground(
                    text,
                    allEntities: entities,
                    excludedIds: excluded
                )
            }

            let redactedAttr = Self.buildRedactedAttributedBackground(
                redacted,
                activeEntities: active
            )

            let restoredAttr: AttributedString? = {
                guard let text = restored, !text.isEmpty else { return nil }
                return Self.buildRestoredAttributedBackground(text, allEntities: entities)
            }()

            // Check cancellation before updating UI
            guard !Task.isCancelled else { return }

            // Update on main thread
            await MainActor.run {
                self?.cachedOriginalAttributed = originalAttr
                self?.cachedRedactedAttributed = redactedAttr
                self?.cachedRestoredAttributed = restoredAttr
                self?.isBuilding = false
            }
        }
    }

    /// Rebuild only the restored text cache
    func rebuildRestoredCache(restoredText: String) {
        let entities = storedAllEntities

        buildTask?.cancel()
        isBuilding = true

        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            let restoredAttr = Self.buildRestoredAttributedBackground(
                restoredText,
                allEntities: entities
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.cachedRestoredAttributed = restoredAttr
                self?.isBuilding = false
            }
        }
    }

    /// Clear all caches
    func clearAll() {
        buildTask?.cancel()
        cachedOriginalAttributed = nil
        cachedRedactedAttributed = nil
        cachedRestoredAttributed = nil
        storedAllEntities = []
        isBuilding = false
    }

    // MARK: - Static Background Build Methods (Thread-Safe, nonisolated)

    nonisolated private static func buildOriginalAttributedBackground(
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

    nonisolated private static func buildRedactedAttributedBackground(
        _ text: String,
        activeEntities: [Entity]
    ) -> AttributedString {
        var attributedString = AttributedString(text)
        attributedString.font = NSFont.systemFont(ofSize: 14)
        attributedString.foregroundColor = NSColor.labelColor

        for entity in activeEntities {
            let code = entity.replacementCode
            var searchStart = attributedString.startIndex

            while searchStart < attributedString.endIndex {
                let searchRange = searchStart..<attributedString.endIndex
                if let range = attributedString[searchRange].range(of: code) {
                    attributedString[range].backgroundColor = NSColor(entity.type.highlightColor)
                    attributedString[range].foregroundColor = NSColor.labelColor
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }

        return attributedString
    }

    nonisolated private static func buildRestoredAttributedBackground(
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
