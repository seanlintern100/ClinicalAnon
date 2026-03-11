//
//  ClipboardHelper.swift
//  Redactor
//
//  Purpose: Shared clipboard utilities for formatted text copying
//  Organization: 3 Big Things
//

import AppKit

// MARK: - Clipboard Helper

enum ClipboardHelper {

    /// Copy text to clipboard with RTF formatting (for Word compatibility) plus plain text fallback
    static func copyFormatted(_ markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let rtfData = MarkdownParser.parseToRTFData(markdown) {
            pasteboard.setData(rtfData, forType: .rtf)
            pasteboard.setString(markdown, forType: .string)
        } else {
            pasteboard.setString(markdown, forType: .string)
        }
    }

    /// Copy plain text to clipboard
    static func copyPlain(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
