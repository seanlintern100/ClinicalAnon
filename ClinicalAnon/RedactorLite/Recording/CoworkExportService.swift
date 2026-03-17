//
//  CoworkExportService.swift
//  Redactor Lite
//
//  Purpose: Saves redacted transcript chunks as JSON to a Cowork-monitored folder
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Chunk JSON Models

struct ChunkSegmentJSON: Codable {
    let speaker: String
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct ChunkJSON: Codable {
    let chunk_index: Int
    let timestamp_start: TimeInterval
    let timestamp_end: TimeInterval
    let segments: [ChunkSegmentJSON]
}

// MARK: - Cowork Export Service

@MainActor
class CoworkExportService: ObservableObject {

    // MARK: - Published State

    @Published var exportRootFolderURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published private(set) var chunksExported: Int = 0
    @Published private(set) var lastExportError: String?

    // MARK: - Internal State

    private var chunkCounter: Int = 0
    private var lastExportedSegmentCount: Int = 0

    // MARK: - UserDefaults Keys

    private static let rootFolderBookmarkKey = "cowork.exportFolderBookmark"

    // MARK: - Initialization

    init() {
        restoreRootFolder()
    }

    // MARK: - Root Folder Management

    /// Whether a root folder has been selected
    var hasRootFolder: Bool {
        exportRootFolderURL != nil
    }

    /// Set the root export folder (from NSOpenPanel) and persist as bookmark
    func setRootFolder(_ url: URL) {
        exportRootFolderURL = url
        persistRootFolder(url)
    }

    /// Persist folder as security-scoped bookmark
    private func persistRootFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.rootFolderBookmarkKey)
        } catch {
            print("CoworkExportService: Failed to save bookmark: \(error)")
        }
    }

    /// Restore folder from persisted bookmark
    private func restoreRootFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.rootFolderBookmarkKey) else {
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Re-persist to refresh
                persistRootFolder(url)
            }
            exportRootFolderURL = url
        } catch {
            print("CoworkExportService: Failed to restore bookmark: \(error)")
        }
    }

    // MARK: - Session Lifecycle

    /// Start a new export session — creates folder and writes session_info.json
    func startSession(metadata: SessionMetadata) throws {
        guard let rootURL = exportRootFolderURL else {
            throw CoworkExportError.noRootFolder
        }

        // Start accessing security-scoped resource
        guard rootURL.startAccessingSecurityScopedResource() else {
            throw CoworkExportError.accessDenied
        }

        let folderURL = rootURL.appendingPathComponent(metadata.folderName, isDirectory: true)

        // Create session folder
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        sessionFolderURL = folderURL
        chunkCounter = 0
        chunksExported = 0
        lastExportedSegmentCount = 0
        lastExportError = nil

        // Write session_info.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let infoData = try encoder.encode(metadata)
        let infoURL = folderURL.appendingPathComponent("session_info.json")
        try infoData.write(to: infoURL, options: .atomic)

        metadata.saveAsLastUsed()
        print("CoworkExportService: Session started at \(folderURL.path)")
    }

    /// Write a new chunk of redacted transcript
    func writeChunk(for session: LiveSession) {
        guard let folderURL = sessionFolderURL else {
            lastExportError = "No session folder"
            return
        }

        let allSegments = session.transcriptSegments
        guard allSegments.count > lastExportedSegmentCount else {
            return  // No new segments since last export
        }

        // Get only the new segments since last export
        let newSegments = Array(allSegments.dropFirst(lastExportedSegmentCount))
        lastExportedSegmentCount = allSegments.count

        chunkCounter += 1

        // Build redacted segments using entity mapping
        let mapping = session.entityMapping
        let chunkSegments: [ChunkSegmentJSON] = newSegments.map { segment in
            var text = segment.text

            // Apply redaction using entity mapping
            for entity in session.detectedEntities {
                let code = mapping.existingMapping(for: entity.originalText.lowercased()) ?? entity.replacementCode
                text = text.replacingOccurrences(
                    of: entity.originalText,
                    with: "[\(code)]",
                    options: .caseInsensitive
                )
            }

            let speakerLabel = speakerLabel(for: segment)

            return ChunkSegmentJSON(
                speaker: speakerLabel,
                text: text,
                start: segment.startTime,
                end: segment.endTime
            )
        }

        let chunk = ChunkJSON(
            chunk_index: chunkCounter,
            timestamp_start: newSegments.first?.startTime ?? 0,
            timestamp_end: newSegments.last?.endTime ?? 0,
            segments: chunkSegments
        )

        // Write chunk file
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let chunkData = try encoder.encode(chunk)
            let filename = String(format: "chunk_%03d.json", chunkCounter)
            let chunkURL = folderURL.appendingPathComponent(filename)
            try chunkData.write(to: chunkURL, options: .atomic)
            chunksExported = chunkCounter
            lastExportError = nil
            print("CoworkExportService: Wrote \(filename) (\(newSegments.count) segments)")
        } catch {
            lastExportError = "Failed to write chunk: \(error.localizedDescription)"
            print("CoworkExportService: Error writing chunk: \(error)")
        }
    }

    /// Finalize the session export
    func finalizeSession() {
        if let rootURL = exportRootFolderURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
        sessionFolderURL = nil
        print("CoworkExportService: Session finalized (\(chunksExported) chunks exported)")
    }

    // MARK: - Speaker Label Mapping

    private func speakerLabel(for segment: TranscriptSegment) -> String {
        switch segment.speaker {
        case .clinician:
            return "therapist"
        case .other:
            // Use diarization speaker ID if available for multi-client
            if let speakerId = segment.speakerId {
                return "client_\(speakerId)"
            }
            return "client"
        }
    }
}

// MARK: - Errors

enum CoworkExportError: Error, LocalizedError {
    case noRootFolder
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .noRootFolder:
            return "No export folder selected. Please choose a folder in settings."
        case .accessDenied:
            return "Cannot access the export folder. Please re-select it in settings."
        }
    }
}
