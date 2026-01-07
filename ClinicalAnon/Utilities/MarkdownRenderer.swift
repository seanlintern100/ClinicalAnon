//
//  MarkdownRenderer.swift
//  ClinicalAnon
//
//  Purpose: Renders markdown content as styled SwiftUI views
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Markdown Renderer

/// Renders markdown text as styled SwiftUI views using the app's DesignSystem
struct MarkdownRenderer: View {

    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case heading1(String)
        case heading2(String)
        case heading3(String)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case table(headers: [String], rows: [[String]])
        case horizontalRule
        case importantCallout(String)
    }

    // MARK: - Parsing

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading 1
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(.heading1(text))
                i += 1
                continue
            }

            // Heading 2
            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(3))
                blocks.append(.heading2(text))
                i += 1
                continue
            }

            // Heading 3
            if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                blocks.append(.heading3(text))
                i += 1
                continue
            }

            // Table (starts with |)
            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                if let table = parseTable(tableLines) {
                    blocks.append(table)
                }
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if currentLine.hasPrefix("- ") {
                        items.append(String(currentLine.dropFirst(2)))
                        i += 1
                    } else if currentLine.hasPrefix("* ") {
                        items.append(String(currentLine.dropFirst(2)))
                        i += 1
                    } else if currentLine.isEmpty {
                        // Check if next non-empty line continues the list
                        var nextNonEmpty = i + 1
                        while nextNonEmpty < lines.count && lines[nextNonEmpty].trimmingCharacters(in: .whitespaces).isEmpty {
                            nextNonEmpty += 1
                        }
                        if nextNonEmpty < lines.count {
                            let nextLine = lines[nextNonEmpty].trimmingCharacters(in: .whitespaces)
                            if nextLine.hasPrefix("- ") || nextLine.hasPrefix("* ") {
                                i += 1
                                continue
                            }
                        }
                        break
                    } else {
                        break
                    }
                }
                if !items.isEmpty {
                    blocks.append(.bulletList(items))
                }
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let currentLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = currentLine.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        let text = String(currentLine[range.upperBound...])
                        items.append(text)
                        i += 1
                    } else if currentLine.isEmpty {
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty {
                    blocks.append(.numberedList(items))
                }
                continue
            }

            // Check for **Important:** callout
            if trimmed.hasPrefix("**Important:**") || trimmed.hasPrefix("**Important**") {
                let text = trimmed
                    .replacingOccurrences(of: "**Important:**", with: "")
                    .replacingOccurrences(of: "**Important**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.importantCallout(text.isEmpty ? "Important" : text))
                i += 1
                continue
            }

            // Regular paragraph - collect consecutive non-special lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let currentLine = lines[i]
                let currentTrimmed = currentLine.trimmingCharacters(in: .whitespaces)

                // Stop at special elements
                if currentTrimmed.isEmpty ||
                   currentTrimmed.hasPrefix("#") ||
                   currentTrimmed.hasPrefix("|") ||
                   currentTrimmed.hasPrefix("- ") ||
                   currentTrimmed.hasPrefix("* ") ||
                   currentTrimmed == "---" ||
                   currentTrimmed == "***" ||
                   currentTrimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                    break
                }

                paragraphLines.append(currentTrimmed)
                i += 1
            }

            if !paragraphLines.isEmpty {
                let paragraphText = paragraphLines.joined(separator: " ")
                blocks.append(.paragraph(paragraphText))
            }
        }

        return blocks
    }

    private func parseTable(_ lines: [String]) -> Block? {
        guard lines.count >= 2 else { return nil }

        // Parse header row
        let headerLine = lines[0]
        let headers = parseTableRow(headerLine)

        // Skip separator row (|---|---|)
        // Parse data rows
        var rows: [[String]] = []
        for i in 2..<lines.count {
            let row = parseTableRow(lines[i])
            if !row.isEmpty {
                rows.append(row)
            }
        }

        return .table(headers: headers, rows: rows)
    }

    private func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells = trimmed.components(separatedBy: "|")

        // Remove empty first and last elements from leading/trailing pipes
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }

        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Rendering

    // Font sizes matching Settings menu
    private let titleFont: Font = .system(size: 15, weight: .semibold)
    private let sectionFont: Font = .system(size: 13, weight: .semibold)
    private let bodyFont: Font = .system(size: 13)
    private let bodyBoldFont: Font = .system(size: 13, weight: .semibold)
    private let captionFont: Font = .system(size: 12)

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading1(let text):
            Text(text)
                .font(titleFont)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
                .padding(.top, 28)  // More space above page title
                .padding(.bottom, 12)

        case .heading2(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DesignSystem.Colors.primaryTeal)
                    .frame(width: 2)

                Text(text)
                    .font(sectionFont)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(.leading, DesignSystem.Spacing.small)
            }
            .padding(.top, 24)  // 24px above section headings
            .padding(.bottom, 8)

        case .heading3(let text):
            // Paragraph headings - just bold
            Text(text)
                .font(bodyBoldFont)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .padding(.top, 16)  // Space above paragraph headings
                .padding(.bottom, 4)

        case .paragraph(let text):
            renderStyledText(text)
                .font(bodyFont)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineSpacing(6)  // ~1.5 line height at 13pt
                .padding(.bottom, 12)  // 12px below paragraphs

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {  // More space between list items
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                        Circle()
                            .fill(DesignSystem.Colors.primaryTeal)
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)

                        renderStyledText(item)
                            .font(bodyFont)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineSpacing(5)
                    }
                }
            }
            .padding(.bottom, 12)  // Space after list
            .padding(.leading, DesignSystem.Spacing.xs)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {  // More space between list items
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                        Text("\(index + 1).")
                            .font(bodyFont)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                            .frame(width: 16, alignment: .trailing)

                        renderStyledText(item)
                            .font(bodyFont)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineSpacing(5)
                    }
                }
            }
            .padding(.bottom, 12)  // Space after list
            .padding(.leading, DesignSystem.Spacing.xs)

        case .table(let headers, let rows):
            renderTable(headers: headers, rows: rows)
                .padding(.top, 8)
                .padding(.bottom, 16)

        case .horizontalRule:
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 1)
                .padding(.vertical, 20)

        case .importantCallout(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DesignSystem.Colors.orange)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Important")
                        .font(bodyBoldFont)
                        .foregroundColor(DesignSystem.Colors.orange)

                    if !text.isEmpty && text != "Important" {
                        renderStyledText(text)
                            .font(bodyFont)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineSpacing(5)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.small)
                .padding(.vertical, DesignSystem.Spacing.small)
            }
            .background(DesignSystem.Colors.sand.opacity(0.3))
            .cornerRadius(DesignSystem.CornerRadius.small)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Styled Text (Bold/Inline Code)

    @ViewBuilder
    private func renderStyledText(_ text: String) -> some View {
        Text(parseInlineStyles(text))
    }

    private func parseInlineStyles(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Handle bold text (**text**)
        let boldPattern = #"\*\*([^*]+)\*\*"#
        if let regex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)

            for match in matches.reversed() {
                if let swiftRange = Range(match.range, in: text),
                   let contentRange = Range(match.range(at: 1), in: text) {
                    let boldText = String(text[contentRange])
                    var boldAttr = AttributedString(boldText)
                    boldAttr.font = .system(size: 13, weight: .semibold)

                    if let attrRange = result.range(of: String(text[swiftRange])) {
                        result.replaceSubrange(attrRange, with: boldAttr)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Table Rendering

    @ViewBuilder
    private func renderTable(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DesignSystem.Spacing.small)
                        .padding(.vertical, DesignSystem.Spacing.xs)
                        .background(DesignSystem.Colors.primaryTeal.opacity(0.1))

                    if index < headers.count - 1 {
                        Rectangle()
                            .fill(DesignSystem.Colors.border)
                            .frame(width: 1)
                    }
                }
            }

            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 1)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { cellIndex, cell in
                        renderStyledText(cell)
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DesignSystem.Spacing.small)
                            .padding(.vertical, DesignSystem.Spacing.xs)
                            .background(rowIndex % 2 == 0 ? Color.clear : DesignSystem.Colors.surface.opacity(0.5))

                        if cellIndex < row.count - 1 {
                            Rectangle()
                                .fill(DesignSystem.Colors.border)
                                .frame(width: 1)
                        }
                    }
                }

                if rowIndex < rows.count - 1 {
                    Rectangle()
                        .fill(DesignSystem.Colors.border.opacity(0.5))
                        .frame(height: 1)
                }
            }
        }
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct MarkdownRenderer_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            MarkdownRenderer(markdown: """
            # Sample Heading

            ## Section Title

            This is a paragraph with **bold text** and regular text.

            ### Subsection

            - First bullet point
            - Second bullet point with **bold**
            - Third point

            1. First numbered item
            2. Second numbered item

            | Header 1 | Header 2 |
            |----------|----------|
            | Cell 1   | Cell 2   |
            | Cell 3   | Cell 4   |

            ---

            **Important:** This is an important callout.

            Regular paragraph after the callout.
            """)
            .padding()
        }
        .frame(width: 600, height: 800)
    }
}
#endif
