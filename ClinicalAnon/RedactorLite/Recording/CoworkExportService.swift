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
    let timestamp: String
}

struct ChunkJSON: Codable {
    let chunk_index: Int
    let session_id: String
    let timestamp_start: String
    let timestamp_end: String
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
    private var sessionId: String = ""

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

    /// Start a new export session — creates folder and writes session_info.json + entity_map.json
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
        sessionId = metadata.folderName
        chunkCounter = 0
        chunksExported = 0
        lastExportedSegmentCount = 0
        lastExportError = nil

        // Write session_info.json (spec-compliant format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let goals = metadata.sessionGoals
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let sessionInfo: [String: Any] = [
            "session_id": sessionId,
            "session_type": metadata.sessionType.rawValue.lowercased(),
            "session_date": dateFormatter.string(from: metadata.sessionDate),
            "session_duration_minutes": metadata.sessionLengthMinutes,
            "therapist_goals": goals,
            "entity_map_version": "1"
        ]

        let infoData = try JSONSerialization.data(withJSONObject: sessionInfo, options: [.prettyPrinted, .sortedKeys])
        let infoURL = folderURL.appendingPathComponent("session_info.json")
        try infoData.write(to: infoURL, options: .atomic)

        // Write initial entity_map.json (empty)
        let initialMap: [String: Any] = [
            "version": "1",
            "mappings": [String: String]()
        ]
        let mapData = try JSONSerialization.data(withJSONObject: initialMap, options: [.prettyPrinted, .sortedKeys])
        let mapURL = folderURL.appendingPathComponent("entity_map.json")
        try mapData.write(to: mapURL, options: .atomic)

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
                // Normalize: strip ALL brackets first, then wrap exactly once
                var bare = code
                while bare.hasPrefix("[") && bare.hasSuffix("]") {
                    bare = String(bare.dropFirst().dropLast())
                }
                let replacement = "[\(bare)]"
                text = text.replacingOccurrences(
                    of: entity.originalText,
                    with: replacement,
                    options: .caseInsensitive
                )
            }

            let speakerLabel = speakerLabel(for: segment)

            return ChunkSegmentJSON(
                speaker: speakerLabel,
                text: text,
                timestamp: formatTimestamp(segment.startTime)
            )
        }

        let chunk = ChunkJSON(
            chunk_index: chunkCounter,
            session_id: sessionId,
            timestamp_start: formatTimestamp(newSegments.first?.startTime ?? 0),
            timestamp_end: formatTimestamp(newSegments.last?.endTime ?? 0),
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

        // Update entity_map.json with current mappings
        updateEntityMap(for: session)
    }

    /// Finalize the session export — writes session_complete.json marker
    func finalizeSession() {
        // Write completion marker so Cowork knows to stop polling
        if let folderURL = sessionFolderURL {
            let marker: [String: Any] = [
                "session_id": sessionId,
                "chunks_exported": chunksExported,
                "completed_at": {
                    let f = ISO8601DateFormatter()
                    f.timeZone = .current
                    f.formatOptions = [.withInternetDateTime]
                    return f.string(from: Date())
                }()
            ]
            if let data = try? JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys]) {
                let markerURL = folderURL.appendingPathComponent("session_complete.json")
                try? data.write(to: markerURL, options: .atomic)
            }
        }

        if let rootURL = exportRootFolderURL {
            rootURL.stopAccessingSecurityScopedResource()
        }
        sessionFolderURL = nil
        sessionId = ""
        print("CoworkExportService: Session finalized (\(chunksExported) chunks exported)")
    }

    // MARK: - Entity Map Export

    /// Write current entity mappings to entity_map.json (replacement code → original text)
    private func updateEntityMap(for session: LiveSession) {
        guard let folderURL = sessionFolderURL else { return }

        // Build inverted mapping: replacement code → original text
        // allMappings returns (original, replacement) tuples
        var invertedMap: [String: String] = [:]
        for mapping in session.entityMapping.allMappings {
            // Strip all brackets from replacement for clean keys: "[PERSON_A]" → "PERSON_A"
            var code = mapping.replacement
            while code.hasPrefix("[") && code.hasSuffix("]") {
                code = String(code.dropFirst().dropLast())
            }
            invertedMap[code] = mapping.original
        }

        let entityMap: [String: Any] = [
            "version": "1",
            "mappings": invertedMap
        ]

        do {
            let mapData = try JSONSerialization.data(withJSONObject: entityMap, options: [.prettyPrinted, .sortedKeys])
            let mapURL = folderURL.appendingPathComponent("entity_map.json")
            try mapData.write(to: mapURL, options: .atomic)
        } catch {
            print("CoworkExportService: Failed to update entity map: \(error)")
        }
    }

    // MARK: - Formatting Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
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
