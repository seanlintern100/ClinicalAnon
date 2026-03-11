//
//  FastTextView.swift
//  Redactor
//
//  Purpose: NSTextView wrapper for fast rendering of large AttributedStrings.
//           SwiftUI's Text is extremely slow for large documents (20-30s for 152K chars).
//           NSTextView renders the same content in <1s.
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Custom NSTextView with Context Menu

/// NSTextView subclass that adds "Add as entity" and "Remove from entities" to right-click menu
class FastTextViewWithMenu: NSTextView {
    var onRightClickWithSelection: ((String) -> Void)?
    var onRemoveEntity: ((String) -> Void)?
    var getAnchorName: ((String) -> String?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        // Get selected text
        let selectedRange = self.selectedRange()
        if selectedRange.length > 0,
           let storage = self.textStorage {
            let selectedText = storage.attributedSubstring(from: selectedRange).string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedText.isEmpty {
                // Add custom items at top
                let addItem = NSMenuItem(title: "Add '\(selectedText)' as entity...", action: #selector(addAsEntity), keyEquivalent: "")
                addItem.target = self
                menu.insertItem(addItem, at: 0)

                // For remove, show anchor name if this is a child entity
                let displayName = getAnchorName?(selectedText) ?? selectedText
                let removeItem = NSMenuItem(title: "Remove '\(displayName)' from entities", action: #selector(removeFromEntities), keyEquivalent: "")
                removeItem.target = self
                menu.insertItem(removeItem, at: 1)

                menu.insertItem(NSMenuItem.separator(), at: 2)
            }
        }

        return menu
    }

    @objc private func addAsEntity() {
        let selectedRange = self.selectedRange()
        if selectedRange.length > 0,
           let storage = self.textStorage {
            let selectedText = storage.attributedSubstring(from: selectedRange).string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedText.isEmpty {
                onRightClickWithSelection?(selectedText)
            }
        }
    }

    @objc private func removeFromEntities() {
        let selectedRange = self.selectedRange()
        if selectedRange.length > 0,
           let storage = self.textStorage {
            let selectedText = storage.attributedSubstring(from: selectedRange).string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedText.isEmpty {
                onRemoveEntity?(selectedText)
            }
        }
    }
}

// MARK: - Fast Text View (NSTextView wrapper for performance)

/// NSTextView wrapper for fast rendering of large AttributedStrings
struct FastTextView: NSViewRepresentable {
    let attributedText: AttributedString
    var onRightClick: ((String) -> Void)? = nil
    var onRemoveEntity: ((String) -> Void)? = nil
    var getAnchorName: ((String) -> String?)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        // Create text storage, layout manager, and text container manually for proper setup
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = FastTextViewWithMenu(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.onRightClickWithSelection = onRightClick
        textView.onRemoveEntity = onRemoveEntity
        textView.getAnchorName = getAnchorName

        // Set initial text
        textStorage.setAttributedString(NSAttributedString(attributedText))

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.drawsBackground = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? FastTextViewWithMenu else { return }

        // Update the attributed text
        textView.textStorage?.setAttributedString(NSAttributedString(attributedText))

        // Update callbacks in case they changed
        textView.onRightClickWithSelection = onRightClick
        textView.onRemoveEntity = onRemoveEntity
        textView.getAnchorName = getAnchorName

        // Ensure text container tracks width properly
        let contentWidth = max(scrollView.contentSize.width - 32, 100)
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)

        // Update frame to match scroll view
        textView.minSize = NSSize(width: contentWidth, height: 0)
        textView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
    }
}
