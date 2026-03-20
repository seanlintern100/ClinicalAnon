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

        // Write .claude/skills/live-session/SKILL.md for Cowork slash-command discovery
        let skillDir = coworkFilesURL
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent("live-session", isDirectory: true)
        let skillURL = skillDir.appendingPathComponent("SKILL.md")
        do {
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        } catch {
            print("SessionExportService: Failed to create skills directory: \(error)")
        }
        // Always overwrite so app updates propagate to colleagues
        writeSkillFile(to: skillURL)

        // Write CLAUDE.md in CoWork Files root — Cowork reads this on session start
        let claudeMdURL = coworkFilesURL.appendingPathComponent("CLAUDE.md")
        writeClaudeMd(to: claudeMdURL)
    }

    /// Writes CLAUDE.md so Cowork knows to use /live-session
    private func writeClaudeMd(to url: URL) {
        let content = """
        # Redactor — Cowork Workspace

        When the user says "start a session", "record a session", "begin recording", or anything similar, use the /live-session skill. Do not ask clarifying questions about what kind of session — it is always a clinical recording session via the Redactor app.

        You have MCP tools from the "redactor" server. Use ONLY those tools to interact with the app. Do not write files, create folders, or use bash commands.
        """

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("SessionExportService: Failed to write CLAUDE.md: \(error)")
        }
    }

    /// Writes the Cowork skill file for /live-session slash command
    private func writeSkillFile(to url: URL) {
        let content = """
        ---
        name: live-session
        description: Start a live clinical recording session. Use when user says "start a session", "record a session", or "begin recording". Captures audio, transcribes, redacts PII, and analyses therapy/assessment sessions in real-time via MCP tools connected to the Redactor app.
        ---

        # Live Session Analysis

        ## CRITICAL: Use MCP Tools Only

        You have a connected MCP server called "redactor" with tools to control the Redactor app. **DO NOT write files, create folders, or use bash commands to interact with the app.** Everything goes through MCP tool calls.

        **DO NOT** write trigger files. **DO NOT** look for session folders on disk. **DO NOT** run python scripts. **DO NOT** try to access TEMP Transcripts or any other folder. Use ONLY the MCP tools listed below.

        ---

        ## When the user says "start a session" (or similar)

        ### Step 1: Collect session details

        Ask these as **separate questions**, one at a time:

        1. "What are the client's initials?" (free text, e.g. "JB")
        2. "What type of session?" — Therapy / Coaching / Supervision
        3. "How long?" — 30 / 50 / 80 / 90 minutes (default 50)
        4. "Anyone else joining?" — 1:1 (default) or Multiple speakers
        5. "What are your goals for this session?" (free text, or "General check-in")

        ### Step 2: Launch recording via MCP

        Call `start_recording()` with the collected details. This automatically launches the app if not running, opens the recording window, and starts recording.

        ```
        start_recording(initials="JB", session_type="Therapy", length=50, goals="Explore work stress", multi_speaker=false)
        ```

        Tell the user recording has started. **DO NOT STOP OR WAIT FOR USER INPUT.** Immediately begin Step 3 — start polling for chunks right now.

        ### Step 3: Analysis loop

        **You ARE the loop. Do not stop. Do not ask the user anything. Do not wait for prompts. Keep polling continuously until the session ends.** Repeat every ~10 seconds:

        1. `get_new_chunks(since_index=N)` — N starts at 0, then use `latest_index` from response
        2. If new chunks arrived, analyse each one (see Analysis Rules below)
        3. `get_session_state()` — get current state with pipeline metrics
        4. Merge your analysis into the state (see Merging below)
        5. `write_session_state(updated_json)` — push to the dashboard
        6. `is_session_complete()` — if true, do final analysis and stop
        7. Wait ~10 seconds, go to step 1

        ### Step 4: Session complete

        When `is_session_complete()` returns true:
        - Process any remaining chunks
        - Write final state
        - Tell the user the session is complete with a brief summary

        ---

        ## MCP Tools

        | Tool | Purpose |
        |------|---------|
        | `health_check()` | Check if app is running |
        | `start_recording(initials, session_type, length, goals, multi_speaker)` | Launch app + start recording |
        | `stop_recording()` | Stop recording |
        | `pause_recording()` | Pause recording |
        | `resume_recording()` | Resume recording |
        | `get_session_info()` | Get session metadata |
        | `get_session_state()` | Get current metrics/analysis state |
        | `get_new_chunks(since_index)` | Get transcript chunks since index N |
        | `write_session_state(state_json)` | Write updated session state to dashboard |
        | `is_session_complete()` | Check if recording stopped |

        ---

        ## Analysis Rules

        For each new chunk, analyse the redacted transcript. All text uses entity codes like `[PERSON_A]` — never attempt to resolve these to real names.

        ### Utterance Classification (therapist segments only)

        Classify each therapist utterance in the new chunk:
        - **Q** = Question — any utterance functioning as a question
        - **SR** = Simple Reflection — restates surface content, paraphrases without adding meaning
        - **CR** = Complex Reflection — adds meaning, pursues implication, reflects emotion beneath the surface, double-sided reflections, metaphor-based reflections
        - **EX** = Expert Statement — information, advice, direction, psychoeducation from a position of expertise. Includes giving information, suggesting, directing, confronting. Does NOT include reflections that happen to contain clinical language
        - **O** = Other — greetings, admin, transitions (not counted in metrics)

        Only classify therapist segments from the NEW chunk. Do not re-classify previous chunks.

        ### Agenda Tracking

        - Track progress on therapist goals: `not_discussed` → `partially_discussed` → `fully_discussed` (one-directional, never reverse)
        - Evidence: synthesised one-liners (max 5 "discussed" + 1-2 "gap" items)
        - "discussed" items = what HAS been covered (your synthesis, not quotes)
        - "gap" items = what SHOULD still be explored but hasn't been
        - Replace the full evidence list each time (synthesise, don't append)

        ### Client Agenda Detection

        - Only surface items where client explicitly states intent or therapist and client agree on a focus
        - Passing mentions do not qualify
        - Do not create duplicates of existing items

        ### People & Details

        - Extract people mentioned by their entity codes with roles, relationships, details, events
        - Merge into existing people list — update existing entries, add new ones
        - Include therapist, client, family members, colleagues, etc.

        ### Theme Synthesis

        - Identify verbatim client phrases that are emotionally loaded, self-referential, or linguistically distinctive
        - Theme names: 2-5 words describing the underlying pattern (not surface content)
        - Assign each phrase to an existing theme or create a new one
        - Maintain 3-7 themes. If adding would exceed 7, replace the least significant or merge

        ### Rupture Detection

        Watch for:
        - **Withdrawal** — client turn length drops 40%+, monosyllabic responses, topic deflection
        - **Confrontation** — direct challenge to therapist, frustration, repeated content with emphasis

        Only flag if the signal is clear in the new chunk.

        ### Risk Monitoring

        Flag if you detect:
        - Suicidal ideation, self-harm, harm to others, child safety, acute distress
        - Use clinical judgment, not keyword matching
        - Risk is persistent once flagged — never cleared during a session

        ### Diarization Echo Detection

        Transcripts may contain echo artefacts — the SAME speech as both therapist and client at near-identical timestamps (within 2 seconds). Skip echo segments entirely.

        ---

        ## Merging Analysis Into State

        When you call `get_session_state()`, you get the current state including pipeline-computed metrics (speaker totals, engagement). Your job is to ADD your analysis:

        - **utterance_counts**: increment `therapist_questions`, `therapist_sr`, `therapist_cr`, `therapist_ex` from your classifications. Recalculate `rq_ratio = (sr + cr) / questions` and `ex_pct = ex / (q + sr + cr + ex) * 100`
        - **therapist_agenda**: update status and evidence for each goal
        - **client_agenda**: add new items if detected
        - **themes**: add phrases, create/rename/merge themes
        - **people**: add/update people entries
        - **rupture**: set `detected: true` and `type` if signal found
        - **risk**: set `flagged: true` if signal found

        Then call `write_session_state()` with the COMPLETE merged JSON (preserve all existing fields, add your updates).

        ---

        ## Session State Schema

        ```json
        {
          "session_id": "JB_2026-03-20_0937",
          "session_type": "therapy",
          "session_date": "2026-03-20",
          "session_duration_seconds": 3000,
          "chunks_processed": 5,
          "last_chunk_timestamp": "00:05:00",
          "speaker_totals": {
            "therapist_seconds": 120.5,
            "client_seconds": 180.3,
            "client_talk_pct": 60.0
          },
          "utterance_counts": {
            "therapist_questions": 12,
            "therapist_sr": 3,
            "therapist_cr": 8,
            "therapist_ex": 2,
            "rq_ratio": 0.92,
            "ex_pct": 8.0
          },
          "engagement": {
            "session_score": 72.5,
            "mean_client_words_per_turn": 35.2,
            "elaborated_turns": 8,
            "total_client_turns": 15
          },
          "therapist_agenda": [
            {
              "id": "ta1",
              "text": "Explore work stress",
              "status": "partially_discussed",
              "evidence": [
                {"type": "discussed", "text": "Identified conflict with manager as primary stressor"},
                {"type": "gap", "text": "Impact on sleep not yet explored"}
              ]
            }
          ],
          "client_agenda": [],
          "people": [
            {"token": "[PERSON_A]", "role": "client", "details": {}, "events": []}
          ],
          "themes": [
            {"id": "th1", "text": "Workplace powerlessness", "phrases": ["I have no say in anything"]}
          ],
          "rupture": {"detected": false, "type": null},
          "risk": {"flagged": false}
        }
        ```

        ## Privacy & Entity Code Format

        All transcript text is redacted. Entity codes like `[PERSON_A]`, `[LOCATION_B]` are placeholders for real names. You must NEVER attempt to resolve these codes. The app handles re-substitution for display only.

        **CRITICAL: When writing entity codes in session state, ALWAYS use square brackets.** Write `[PERSON_A]` not `PERSON_A`. Write `[ORG_B]` not `ORG_B`. The dashboard uses these brackets to find and replace codes with real names. If you omit brackets, the real name will not display.
        """

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("SessionExportService: Wrote SKILL.md")
        } catch {
            print("SessionExportService: Failed to write SKILL.md: \(error)")
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
        privateFolderURL = privateFolderForClient  // Update to client-specific Private/{initials}/
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

        // Keep sessionFolderURL and privateFolderURL so dashboard continues showing final state
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
            // privateFolderURL is already Private/{initials}/ — don't append initials again
            let mapURL = privateRoot.appendingPathComponent("entity_map.json")
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
