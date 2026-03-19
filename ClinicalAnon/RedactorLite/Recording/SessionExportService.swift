//
//  SessionExportService.swift
//  Redactor Lite
//
//  Purpose: Saves redacted transcript chunks as JSON to the workspace
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Chunk JSON Models

struct ChunkSegmentJSON: Codable {
    let speaker: String
    let text: String
    let timestamp: String
    let timestamp_end: String
}

struct ChunkJSON: Codable {
    let chunk_index: Int
    let session_id: String
    let timestamp_start: String
    let timestamp_end: String
    let segments: [ChunkSegmentJSON]
}

// MARK: - Session Export Service

@MainActor
class SessionExportService: ObservableObject {

    // MARK: - Published State

    @Published var exportRootFolderURL: URL?
    @Published private(set) var privateFolderURL: URL?
    @Published private(set) var sessionFolderURL: URL?
    @Published private(set) var chunksExported: Int = 0
    @Published private(set) var lastExportError: String?

    // MARK: - Internal State

    private var chunkCounter: Int = 0
    private var lastExportedSegmentCount: Int = 0
    private var sessionId: String = ""
    private var currentInitials: String = ""

    // MARK: - UserDefaults Keys

    private static let rootFolderBookmarkKey = "export.customFolderBookmark"

    // MARK: - Workspace Paths

    /// Fixed workspace root at ~/Library/Application Support/Redactor/Workspace/
    private static var defaultWorkspaceURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Redactor", isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
    }

    /// The workspace root directory
    var workspaceURL: URL {
        Self.defaultWorkspaceURL
    }

    /// Whether workspace exists (always true after init)
    var hasRootFolder: Bool {
        true
    }

    // MARK: - Initialization

    init() {
        ensureWorkspace()
        exportRootFolderURL = workspaceURL.appendingPathComponent("Sessions", isDirectory: true)
        privateFolderURL = workspaceURL.appendingPathComponent("Private", isDirectory: true)
    }

    // MARK: - Workspace Setup

    /// Creates the 3-folder workspace structure if it doesn't exist
    private func ensureWorkspace() {
        let fm = FileManager.default
        let sessionsURL = workspaceURL.appendingPathComponent("Sessions", isDirectory: true)
        let privateURL = workspaceURL.appendingPathComponent("Private", isDirectory: true)
        let coworkFilesURL = workspaceURL.appendingPathComponent("CoWork Files", isDirectory: true)

        do {
            try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: privateURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: coworkFilesURL, withIntermediateDirectories: true)
        } catch {
            print("SessionExportService: Failed to create workspace: \(error)")
        }

        // Write INSTRUCTIONS.md if it doesn't exist
        let instructionsURL = coworkFilesURL.appendingPathComponent("INSTRUCTIONS.md")
        if !fm.fileExists(atPath: instructionsURL.path) {
            writeInstructions(to: instructionsURL)
        }
    }

    /// Writes the AI copilot instructions file
    private func writeInstructions(to url: URL) {
        let content = """
        # Live Session Analysis — Folder Instructions

        ## CRITICAL: Use MCP Tools Only

        You have a connected MCP server called "redactor" with tools to control the Redactor app. **DO NOT write files, create folders, or use bash commands to interact with the app.** Everything goes through MCP tool calls.

        **DO NOT** write trigger files. **DO NOT** look for session folders on disk. **DO NOT** run python scripts. Use the MCP tools listed below.

        ## When the user says "start a session" (or similar)

        ### Step 1: Collect session details
        Ask for: Client initials, Session type, Session length, Number of speakers, Session goals

        ### Step 2: Launch recording via MCP
        Call: `start_recording(initials="XX", session_type="Therapy", length=50, goals="...", multi_speaker=false)`

        ### Step 3: Analysis loop (repeat until session ends)
        Every ~10 seconds:
        1. `get_new_chunks(since_index=N)` — get new transcript chunks
        2. Analyse each chunk (utterance classification, agenda tracking, themes, people, rupture, risk)
        3. `get_session_state()` — get current metrics
        4. Merge your analysis into the state
        5. `write_session_state(updated_json)` — push to dashboard
        6. `is_session_complete()` — if true, final summary and stop

        ## MCP Tools
        | Tool | Purpose |
        |------|---------|
        | `health_check()` | Check if app is running |
        | `start_recording(initials, session_type, length, goals, multi_speaker)` | Launch app + start recording |
        | `stop_recording()` | Stop recording |
        | `get_session_state()` | Get current metrics/analysis |
        | `get_new_chunks(since_index)` | Get transcript chunks since index N |
        | `write_session_state(state_json)` | Write updated session state |
        | `is_session_complete()` | Check if recording stopped |

        ## Privacy
        All transcript text is redacted. Entity codes like [PERSON_A] are placeholders. Never attempt to resolve these to real names.
        """

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("SessionExportService: Wrote INSTRUCTIONS.md")
        } catch {
            print("SessionExportService: Failed to write INSTRUCTIONS.md: \(error)")
        }
    }

    // MARK: - Custom Folder (Bookmark Fallback)

    /// Set a custom root export folder (from NSOpenPanel) and persist as bookmark
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
            print("SessionExportService: Failed to save bookmark: \(error)")
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
                persistRootFolder(url)
            }
            exportRootFolderURL = url
        } catch {
            print("SessionExportService: Failed to restore bookmark: \(error)")
        }
    }

    // MARK: - Session Lifecycle

    /// Start a new export session — creates session folder and writes session_info.json + entity_map.json
    func startSession(metadata: SessionMetadata) throws {
        guard let sessionsRoot = exportRootFolderURL else {
            throw SessionExportError.noRootFolder
        }

        let initials = metadata.clientInitials.trimmingCharacters(in: .whitespaces).uppercased()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateStr = dateFormatter.string(from: metadata.sessionDate)

        // Sessions/{initials}/{date}/
        let folderURL = sessionsRoot
            .appendingPathComponent(initials, isDirectory: true)
            .appendingPathComponent(dateStr, isDirectory: true)

        // Create session folder
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // Private/{initials}/
        guard let privateRoot = privateFolderURL else {
            throw SessionExportError.noRootFolder
        }
        let privateFolderForClient = privateRoot.appendingPathComponent(initials, isDirectory: true)
        try FileManager.default.createDirectory(at: privateFolderForClient, withIntermediateDirectories: true)

        sessionFolderURL = folderURL
        sessionId = "\(initials)_\(dateStr)"
        currentInitials = initials
        chunkCounter = 0
        chunksExported = 0
        lastExportedSegmentCount = 0
        lastExportError = nil

        // Write session_info.json
        let infoDateFormatter = DateFormatter()
        infoDateFormatter.dateFormat = "yyyy-MM-dd"

        let goals = metadata.sessionGoals
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let sessionInfo: [String: Any] = [
            "session_id": sessionId,
            "session_type": metadata.sessionType.rawValue.lowercased(),
            "session_date": infoDateFormatter.string(from: metadata.sessionDate),
            "session_duration_minutes": metadata.sessionLengthMinutes,
            "therapist_goals": goals,
            "entity_map_version": "1"
        ]

        let infoData = try JSONSerialization.data(withJSONObject: sessionInfo, options: [.prettyPrinted, .sortedKeys])
        let infoURL = folderURL.appendingPathComponent("session_info.json")
        try infoData.write(to: infoURL, options: .atomic)

        // Write initial entity_map.json to Private/{initials}/
        let initialMap: [String: Any] = [
            "version": "1",
            "mappings": [String: String]()
        ]
        let mapData = try JSONSerialization.data(withJSONObject: initialMap, options: [.prettyPrinted, .sortedKeys])
        let mapURL = privateFolderForClient.appendingPathComponent("entity_map.json")
        try mapData.write(to: mapURL, options: .atomic)

        metadata.saveAsLastUsed()
        print("SessionExportService: Session started at \(folderURL.path)")
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
                timestamp: formatTimestamp(segment.startTime),
                timestamp_end: formatTimestamp(segment.endTime)
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
            print("SessionExportService: Wrote \(filename) (\(newSegments.count) segments)")
        } catch {
            lastExportError = "Failed to write chunk: \(error.localizedDescription)"
            print("SessionExportService: Error writing chunk: \(error)")
        }

        // Update entity_map.json with current mappings
        updateEntityMap(for: session)
    }

    /// Finalize the session export — writes session_complete.json marker
    func finalizeSession() {
        // Write completion marker
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

        sessionFolderURL = nil
        sessionId = ""
        currentInitials = ""
        print("SessionExportService: Session finalized (\(chunksExported) chunks exported)")
    }

    // MARK: - Entity Map Export

    /// Write current entity mappings to Private/{initials}/entity_map.json
    private func updateEntityMap(for session: LiveSession) {
        guard let privateRoot = privateFolderURL, !currentInitials.isEmpty else { return }

        // Build inverted mapping: replacement code -> original text
        var invertedMap: [String: String] = [:]
        for mapping in session.entityMapping.allMappings {
            // Strip all brackets from replacement for clean keys: "[PERSON_A]" -> "PERSON_A"
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
            let mapURL = privateRoot
                .appendingPathComponent(currentInitials, isDirectory: true)
                .appendingPathComponent("entity_map.json")
            try mapData.write(to: mapURL, options: .atomic)
        } catch {
            print("SessionExportService: Failed to update entity map: \(error)")
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
            if let speakerId = segment.speakerId {
                return "therapist_\(speakerId)"
            }
            return "therapist"
        case .other:
            if let speakerId = segment.speakerId {
                return "client_\(speakerId)"
            }
            return "client"
        }
    }
}

// MARK: - Errors

enum SessionExportError: Error, LocalizedError {
    case noRootFolder
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .noRootFolder:
            return "Workspace folder not available."
        case .accessDenied:
            return "Cannot access the export folder."
        }
    }
}
