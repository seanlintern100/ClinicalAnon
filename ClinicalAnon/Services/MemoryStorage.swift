//
//  MemoryStorage.swift
//  Redactor
//
//  Purpose: Client-side handler for Anthropic memory tool file operations
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Detected Document

/// Represents a document detected in the input text
struct DetectedDocument: Identifiable {
    let id: String
    var title: String
    var author: String?
    var date: String?
    var type: String
    var summary: String
    var fullContent: String

    /// ID of the source document this was detected within (for hierarchy)
    var sourceDocumentId: UUID?

    /// Estimated token count (~4 chars per token)
    var tokenEstimate: Int {
        fullContent.count / 4
    }
}

// MARK: - Document Boundary

/// Represents boundaries detected in multi-document input
struct DocumentBoundary {
    let title: String
    let author: String?
    let date: String?
    let type: String
    let summary: String
    let startsWith: String?
    let startIndex: Int
    let endIndex: Int

    var range: Range<String.Index> {
        fatalError("Use indices with the original string")
    }
}

// MARK: - Memory Storage

/// Handles memory tool file operations for Anthropic's memory tool
@MainActor
class MemoryStorage: ObservableObject {

    // MARK: - Properties

    /// Base directory for memory files
    private let memoryDirectory: URL

    /// Published state for UI binding
    @Published private(set) var files: [String: String] = [:]

    /// Currently loaded documents (for UI display)
    @Published private(set) var documents: [DetectedDocument] = []

    /// Whether memory mode is active
    @Published var isMemoryModeActive: Bool = false

    /// Number of documents in memory (computed from documents array)
    var documentCount: Int {
        documents.count
    }

    // MARK: - Initialization

    init() {
        // Use app's caches directory
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        memoryDirectory = caches.appendingPathComponent("memories", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Memory Tool Command Handler

    /// Handle memory tool calls from AI
    /// - Parameter input: The input dictionary from the tool call
    /// - Returns: Response string to return to the AI
    func handleMemoryCommand(_ input: [String: Any]) -> String {
        guard let command = input["command"] as? String else {
            return "Error: Missing command"
        }

        switch command {
        case "view":
            return handleView(input)
        case "create":
            return handleCreate(input)
        case "str_replace":
            return handleStrReplace(input)
        case "insert":
            return handleInsert(input)
        case "delete":
            return handleDelete(input)
        case "rename":
            return handleRename(input)
        default:
            return "Error: Unknown command '\(command)'"
        }
    }

    // MARK: - View Command

    private func handleView(_ input: [String: Any]) -> String {
        guard let path = input["path"] as? String else {
            return "Error: Missing path"
        }

        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        // Handle root /memories path
        if safePath.isEmpty || safePath == "/" {
            return viewDirectory(memoryDirectory, path: "/memories")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return "The path \(path) does not exist. Please provide a valid path."
        }

        if isDirectory.boolValue {
            return viewDirectory(url, path: path)
        } else {
            return viewFile(url, path: path, range: input["view_range"] as? [Int])
        }
    }

    private func viewDirectory(_ url: URL, path: String) -> String {
        var output = "Here're the files and directories up to 2 levels deep in \(path), excluding hidden items:\n"

        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if enumerator.level > 2 {
                    enumerator.skipDescendants()
                    continue
                }

                let relativePath = fileURL.path.replacingOccurrences(of: memoryDirectory.path, with: "/memories")
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sizeStr = formatFileSize(size)

                output += "\(sizeStr)\t\(relativePath)\n"
            }
        }

        return output
    }

    private func viewFile(_ url: URL, path: String, range: [Int]?) -> String {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: Could not read file at \(path)"
        }

        let lines = content.components(separatedBy: .newlines)

        // Check line limit
        if lines.count > 999_999 {
            return "File \(path) exceeds maximum line limit of 999,999 lines."
        }

        // Limit default view size to prevent payload explosion in memory mode
        let maxDefaultLines = 300
        let needsTruncation = range == nil && lines.count > maxDefaultLines

        var output: String
        let startLine = max((range?.first ?? 1) - 1, 0)
        var endLine: Int

        if needsTruncation {
            endLine = min(maxDefaultLines, lines.count)
            output = "Here's the first \(maxDefaultLines) lines of \(path) (total: \(lines.count) lines):\n"
        } else {
            // Handle negative values (like -1 meaning "to end") and invalid ranges
            let requestedEnd = range?.last ?? lines.count
            if requestedEnd < 0 {
                // Negative value means "to end of file"
                endLine = lines.count
            } else {
                endLine = min(requestedEnd, lines.count)
            }
            output = "Here's the content of \(path) with line numbers:\n"
        }

        // Ensure valid range (endLine >= startLine)
        if endLine < startLine {
            endLine = lines.count
        }

        // Clamp startLine to valid range
        let safeStartLine = min(startLine, lines.count)
        let safeEndLine = min(endLine, lines.count)

        for i in safeStartLine..<safeEndLine {
            let lineNum = String(format: "%6d", i + 1)
            output += "\(lineNum)\t\(lines[i])\n"
        }

        if needsTruncation {
            output += "\n[... \(lines.count - maxDefaultLines) more lines. Use view_range: [start, end] to see specific sections ...]\n"
        }

        return output
    }

    // MARK: - Create Command

    private func handleCreate(_ input: [String: Any]) -> String {
        guard let path = input["path"] as? String,
              let content = input["file_text"] as? String else {
            return "Error: Missing path or file_text"
        }

        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        if FileManager.default.fileExists(atPath: url.path) {
            return "Error: File \(path) already exists"
        }

        // Create parent directories if needed
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            files[safePath] = content
            return "File created successfully at: \(path)"
        } catch {
            return "Error: Could not create file at \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - String Replace Command

    private func handleStrReplace(_ input: [String: Any]) -> String {
        guard let path = input["path"] as? String,
              let oldStr = input["old_str"] as? String,
              let newStr = input["new_str"] as? String else {
            return "Error: Missing path, old_str, or new_str"
        }

        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
            return "Error: The path \(path) does not exist. Please provide a valid path."
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: The path \(path) does not exist. Please provide a valid path."
        }

        // Check for occurrences
        let occurrences = content.ranges(of: oldStr)

        if occurrences.isEmpty {
            return "No replacement was performed, old_str `\(oldStr)` did not appear verbatim in \(path)."
        }

        if occurrences.count > 1 {
            let lines = findLineNumbers(for: oldStr, in: content)
            return "No replacement was performed. Multiple occurrences of old_str `\(oldStr)` in lines: \(lines). Please ensure it is unique"
        }

        // Perform replacement
        let newContent = content.replacingOccurrences(of: oldStr, with: newStr)

        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            files[safePath] = newContent

            // Return success with snippet
            let snippetLines = newContent.components(separatedBy: .newlines)
            var snippet = "The memory file has been edited.\n\nHere's a snippet of the edited section:\n"
            let editedLineIndex = snippetLines.firstIndex { $0.contains(newStr) } ?? 0
            let start = max(0, editedLineIndex - 2)
            let end = min(snippetLines.count, editedLineIndex + 3)
            for i in start..<end {
                let lineNum = String(format: "%6d", i + 1)
                snippet += "\(lineNum)\t\(snippetLines[i])\n"
            }
            return snippet
        } catch {
            return "Error: Could not write to \(path)"
        }
    }

    // MARK: - Insert Command

    private func handleInsert(_ input: [String: Any]) -> String {
        guard let path = input["path"] as? String,
              let insertLine = input["insert_line"] as? Int,
              let insertText = input["insert_text"] as? String else {
            return "Error: Missing path, insert_line, or insert_text"
        }

        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue {
            return "Error: The path \(path) does not exist"
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: The path \(path) does not exist"
        }

        var lines = content.components(separatedBy: .newlines)

        if insertLine < 0 || insertLine > lines.count {
            return "Error: Invalid `insert_line` parameter: \(insertLine). It should be within the range of lines of the file: [0, \(lines.count)]"
        }

        lines.insert(insertText, at: insertLine)
        let newContent = lines.joined(separator: "\n")

        do {
            try newContent.write(to: url, atomically: true, encoding: .utf8)
            files[safePath] = newContent
            return "The file \(path) has been edited."
        } catch {
            return "Error: Could not write to \(path)"
        }
    }

    // MARK: - Delete Command

    private func handleDelete(_ input: [String: Any]) -> String {
        guard let path = input["path"] as? String else {
            return "Error: Missing path"
        }

        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return "Error: The path \(path) does not exist"
        }

        do {
            try FileManager.default.removeItem(at: url)
            files.removeValue(forKey: safePath)
            return "Successfully deleted \(path)"
        } catch {
            return "Error: Could not delete \(path): \(error.localizedDescription)"
        }
    }

    // MARK: - Rename Command

    private func handleRename(_ input: [String: Any]) -> String {
        guard let oldPath = input["old_path"] as? String,
              let newPath = input["new_path"] as? String else {
            return "Error: Missing old_path or new_path"
        }

        let safeOldPath = sanitizePath(oldPath)
        let safeNewPath = sanitizePath(newPath)

        let oldURL = memoryDirectory.appendingPathComponent(safeOldPath)
        let newURL = memoryDirectory.appendingPathComponent(safeNewPath)

        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            return "Error: The path \(oldPath) does not exist"
        }

        if FileManager.default.fileExists(atPath: newURL.path) {
            return "Error: The destination \(newPath) already exists"
        }

        // Create parent directories if needed
        try? FileManager.default.createDirectory(
            at: newURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            if let content = files[safeOldPath] {
                files.removeValue(forKey: safeOldPath)
                files[safeNewPath] = content
            }
            return "Successfully renamed \(oldPath) to \(newPath)"
        } catch {
            return "Error: Could not rename \(oldPath): \(error.localizedDescription)"
        }
    }

    // MARK: - Direct File Access (for app use)

    /// Read a file directly (for embedding index in system prompt)
    func readFile(_ filename: String) -> String? {
        let safePath = sanitizePath(filename)
        let url = memoryDirectory.appendingPathComponent(safePath)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Create a file directly (for app initialization)
    func createFile(path: String, content: String) {
        let safePath = sanitizePath(path)
        let url = memoryDirectory.appendingPathComponent(safePath)

        // Create parent directories if needed
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try? content.write(to: url, atomically: true, encoding: .utf8)
        files[safePath] = content
    }

    // MARK: - Document Management

    /// Create index file from detected documents (with full summaries for embedding)
    func createIndexFile(from detectedDocs: [DetectedDocument]) {
        var indexContent = "# Document Summaries\n\n"

        for doc in detectedDocs {
            indexContent += """
            ## \(doc.id.uppercased()): \(doc.title)
            **Type:** \(doc.type) | **Date:** \(doc.date ?? "Not specified") | **File:** \(doc.id)_content.md

            \(doc.summary)

            ---

            """
        }

        createFile(path: "index.md", content: indexContent)
        documents = detectedDocs
    }

    /// Create individual document content files
    func createDocumentFiles(from detectedDocs: [DetectedDocument]) {
        for doc in detectedDocs {
            createFile(path: "\(doc.id)_content.md", content: doc.fullContent)
        }
    }

    /// Create empty working notes file
    func createWorkingNotesFile() {
        let content = """
        # Working Notes

        ## Active Context
        <!-- Current state, decisions in effect, user preferences -->

        ## Observations
        <!-- Findings from document review, cross-references -->

        ## Superseded
        <!-- Old notes kept for reference, can be deleted -->

        """
        createFile(path: "working_notes.md", content: content)
    }

    // MARK: - Reset

    /// Clear all memory files and reset state
    func reset() {
        try? FileManager.default.removeItem(at: memoryDirectory)
        try? FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        files.removeAll()
        documents.removeAll()
        isMemoryModeActive = false
    }

    // MARK: - Helpers

    /// Prevent path traversal attacks
    private func sanitizePath(_ path: String) -> String {
        var clean = path
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..\\", with: "")
            .replacingOccurrences(of: "%2e%2e%2f", with: "")
            .replacingOccurrences(of: "%2E%2E%2F", with: "")

        // Remove /memories prefix if present
        if clean.hasPrefix("/memories/") {
            clean = String(clean.dropFirst("/memories/".count))
        } else if clean.hasPrefix("/memories") {
            clean = String(clean.dropFirst("/memories".count))
        }

        // Remove leading slash
        if clean.hasPrefix("/") {
            clean = String(clean.dropFirst())
        }

        return clean
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / (1024 * 1024))
    }

    private func findLineNumbers(for text: String, in content: String) -> String {
        var lineNumbers: [Int] = []
        let lines = content.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            if line.contains(text) {
                lineNumbers.append(i + 1)
            }
        }
        return lineNumbers.map(String.init).joined(separator: ", ")
    }
}

// MARK: - String Extension

extension String {
    /// Find all ranges of a substring
    func ranges(of substring: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = startIndex
        while let range = range(of: substring, range: start..<endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}
