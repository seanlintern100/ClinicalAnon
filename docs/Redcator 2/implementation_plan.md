# Redactor v2 — Implementation Plan
## New Build with Service Import from Existing Codebase

---

## Approach

Start a fresh Xcode project with a clean architecture. Import proven services (audio, transcription, redaction, MCP) from the existing Redactor codebase. Build the new data layer (SQLCipher), client management, and UI from scratch.

**Reference documents:**
- `redactor_design_document.md` — Architecture, flows, session lifecycle
- `redactor_cowork_integration_spec.md` — MCP tools, HTTP endpoints, SKILL.md
- `redactor_file_structure.md` — Directory layout, status markers, retention
- `redactor_schema_v3.md` — Database tables, processing status flow
- `Transcript Notes Transofrmation.txt` — Clinical note generation prompt

**Source codebase:** `/Users/seanversteegh/Developer/active/Redactor-v2/ClinicalAnon/`

---

## Build Order

The plan is structured in dependency order. Each phase builds on the previous. Phases cannot be reordered. Steps within a phase can be parallelised where noted.

---

## Phase 1: Project Scaffold

Set up the new Xcode project, folder structure, and dependencies before writing any feature code.

### 1.1 Create Xcode project via xcodegen

Create `project.yml` with a single target (no Lite/Full split). Configure:
- macOS deployment target (match existing: macOS 14+)
- Swift 5.9+
- App sandbox entitlements: microphone, file access
- Bundle identifier: `com.3bigthings.redactor`
- Signing: Developer ID, team 5N8GXZGSZ5

**Dependencies to include:**
- WhisperKit (transcription)
- FluidAudio (speaker diarization)
- WebRTC audio processing (echo cancellation — vendored)
- SQLCipher (new — via CocoaPods or SPM, e.g., GRDB with SQLCipher)

Run `xcodegen generate` and verify clean build.

**Reference:** Design doc Section 2 (Platform and Technology Decisions)

### 1.2 Create folder structure

```
Redactor/
├── App/
│   └── RedactorApp.swift              (app entry point)
├── Data/
│   ├── Database/
│   │   ├── DatabaseManager.swift      (SQLCipher connection, migrations)
│   │   └── Migrations/               (versioned schema migrations)
│   ├── Models/
│   │   ├── Client.swift               (DB model)
│   │   ├── Session.swift              (DB model)
│   │   ├── FeedbackScores.swift       (DB model)
│   │   └── Document.swift             (DB model)
│   └── Repositories/
│       ├── ClientRepository.swift     (CRUD + queries)
│       ├── SessionRepository.swift
│       ├── EntityRepository.swift
│       ├── DocumentRepository.swift
│       └── FeedbackRepository.swift
├── Services/
│   ├── Audio/                         (imported)
│   ├── Transcription/                 (imported)
│   ├── Redaction/                     (imported)
│   ├── Cowork/                        (imported + new)
│   │   ├── CopilotHTTPServer.swift    (imported)
│   │   ├── SessionExportService.swift (imported, modified)
│   │   └── ContentIngestionService.swift (new)
│   ├── Workspace/
│   │   ├── WorkspaceManager.swift     (new — manages workspace file I/O)
│   │   ├── IndexManager.swift         (new — writes index.json, client_index.json)
│   │   └── EntityMapSyncService.swift (new — syncs DB ↔ entity_map.json)
│   └── Session/                       (imported)
├── Views/
│   ├── Onboarding/
│   ├── Caseload/                      (client list)
│   ├── ClientWorkspace/               (client detail, documents, feedback)
│   ├── Recording/                     (imported + adapted)
│   ├── RedactionReview/               (new)
│   └── Documents/                     (document viewer, export)
├── Utilities/                         (imported)
└── Resources/                         (imported — fonts, names, CoreML, MCP server)
```

### 1.3 Import resources

Copy from existing codebase (no modifications):
- `Resources/first_names.txt` + license
- `Resources/nz_places.txt` + license
- `Resources/BERT/` (CoreML model + tokenizer configs)
- `Resources/Assets.xcassets/`
- `Resources/Fonts/`
- `Resources/CopilotMCP/redactor_mcp_server.py`

---

## Phase 2: Data Layer

Build the database, models, and repositories. This is the foundation everything else depends on.

### 2.1 SQLCipher database setup

Create `DatabaseManager.swift`:
- Open/create SQLCipher database at `~/Library/Application Support/Redactor/redactor.db`
- Encryption key from macOS Keychain (generate on first launch, store under `com.3bigthings.redactor.dbkey`)
- Migration system (version-tracked schema changes)

**Reference:** Schema doc (full table definitions), Design doc Section 5

### 2.2 Initial schema migration

Create all tables from `redactor_schema_v3.md`:
- `clinician`
- `clients` (with `initials` UNIQUE)
- `sessions` (with `processing_status`, `workspace_folder`)
- `audio_chunks`
- `transcript_segments`
- `entities`
- `entity_positions`
- `entity_mappings` (with unique constraint on `client_id, persistence_scope, original_text_normalized`)
- `redacted_persons`
- `source_documents`
- `documents` (with `generated_by` field)
- `feedback_scores` (with `narrative_document_id`)
- `practitioner_metrics`
- `report_templates`

### 2.3 Data models

Create Swift structs/classes for each table. Use Codable where appropriate. Include:
- `Client` — with computed property for workspace folder path
- `Session` — with `ProcessingStatus` enum (active, ended, pendingRedaction, redacted, processed)
- `FeedbackScores` — with signal label computation (display-time, not stored)
- `Document` — with `DocumentType` and `GeneratedBy` enums
- `EntityMapping` — with `PersistenceScope` enum

### 2.4 Repositories

Create repository classes for database CRUD:
- `ClientRepository` — create, update, discharge, list active, find by initials, cascade delete
- `SessionRepository` — create, update status, list by client, find unprocessed
- `EntityRepository` — create, promote to persistent, list by client, merge
- `EntityMappingRepository` — client-scoped CRUD, load persistent mappings, first-write-wins enforcement
- `DocumentRepository` — create, list by client/session, delete
- `FeedbackRepository` — create, list by client for longitudinal view
- `PractitionerMetricsRepository` — create/update aggregates

### 2.5 Pre-seeded entity mappings

Implement the auto-creation of CLIENT_A and THERAPIST_A mappings:
- On client creation: create `[CLIENT_A]` mapping (with variants) from `clients.full_legal_name`, `preferred_name`, `title`
- On client creation: copy `[THERAPIST_A]` mapping from `clinician` table
- Both with `persistence_scope = 'client'`, `source = 'system'`
- Cannot be excluded or deleted

**Reference:** Design doc Section 4 (Pre-seeded Entity Mappings), Schema doc (entity_mappings lifecycle)

---

## Phase 3: Workspace Management

Build the file-system layer that manages the workspace directory, index files, and entity map sync.

### 3.1 WorkspaceManager

Create `WorkspaceManager.swift`:
- Ensure workspace directory structure exists on launch (`Sessions/`, `Private/`, `CoWork Files/`)
- Create client folder (`Sessions/{initials}/`) on client creation
- Create empty `rolling_summary.md` on client folder creation
- Create `Private/{initials}/` folder on client creation
- Delete client folders on discharge + 30 days
- Write `client_profile.json` from database data (entity-substituted `preferred_name`)

**Reference:** File structure doc (full directory structure, who writes what)

### 3.2 IndexManager

Create `IndexManager.swift`:
- Write `Sessions/index.json` — root index of all clients
- Write `Sessions/{initials}/client_index.json` — sessions and documents for a client
- Update index on: client create/discharge, session complete, document ingestion
- All content redacted (substitution tokens, no real names)

**Reference:** File structure doc (index.json and client_index.json schemas, update triggers)

### 3.3 EntityMapSyncService

Create `EntityMapSyncService.swift`:
- **On session start:** Export client-scoped mappings from DB → `Private/{initials}/entity_map.json`
- **On session end:** Write promoted mappings back to DB AND update `entity_map.json`
- **Conflict resolution:** DB wins. File is regenerated from DB on next session start.
- File format matches existing `entity_map.json` schema

**Reference:** Design doc Section 4 (entity map sync direction), File structure doc (entity_map.json)

---

## Phase 4: Import Core Services

Import proven services from the existing codebase. Most import as-is. Group into independent service layers.

### 4.1 Audio services (import as-is)

Copy from existing `Services/Audio/`:
- `AECProcessor.swift`
- `AECBridge.h` / `AECBridge.mm`
- `RingBuffer.swift`
- `SpeakerDiarizationService.swift`

Copy from `Services/Session/`:
- `AudioCaptureService.swift`

Verify build. These have no dependencies on app-level code.

### 4.2 Transcription services (import as-is)

Copy:
- `TranscriptionService.swift`
- `TranscriptExportService.swift`
- `Models/TranscriptSegment.swift`
- `Models/TranscriptionGap.swift`

### 4.3 Redaction pipeline (import as-is)

Copy all recognizers from `Services/Recognizers/`:
- `EmailRecognizer.swift`, `NZPhoneRecognizer.swift`, `NZMedicalIDRecognizer.swift`
- `DateRecognizer.swift`, `NZAddressRecognizer.swift`, `MaoriNameRecognizer.swift`
- `RelationshipNameExtractor.swift`, `TitleNameRecognizer.swift`
- `FirstNameDictionaryRecognizer.swift`, `UserInclusionRecognizer.swift`
- `AppleNERRecognizer.swift`, `AllNumbersRecognizer.swift`

Copy core services:
- `EntityRecognizer.swift` (protocol)
- `SwiftNERService.swift` (recognizer chain orchestrator)
- `XLMRobertaNERService.swift` (CoreML NER)
- `EntityDetector.swift`
- `AnonymizationEngine.swift`
- `TextReplacer.swift`
- `LiveRedactor.swift`
- `OverlapDetector.swift`
- `NERUtilities.swift`
- `DateNormalizer.swift`

Copy models:
- `Entity.swift` (includes NameVariant enum — confirms the 7 variants)
- `EntityType.swift`
- `EntityMapping.swift`
- `PIIFinding.swift`
- `AnonymizationResult.swift`

### 4.4 Session management (import with modification)

Copy:
- `SessionManager.swift` — **Modify:** Remove `#if !REDACTOR_LITE` guards and all references to `SessionAssistantService`, `SessionAIService`, `BedrockService`. The new app has no direct AI calls. Keep audio, transcription, redaction, and export orchestration.
- `ChunkManager.swift`
- `SessionStorageService.swift`
- `SessionEncryptionService.swift`

Copy models:
- `LiveSession.swift`
- `AudioChunkReference.swift`
- `SessionMetadata.swift` (from RedactorLite/Recording/)

### 4.5 Utilities (import as-is)

Copy:
- `SettingsKeys.swift`
- `DesignSystem.swift`
- `AppError.swift`
- `MarkdownParser.swift` / `MarkdownRenderer.swift`
- `ClipboardHelper.swift`
- `StringExtensions.swift`
- `UserExclusionManager.swift` / `UserInclusionManager.swift`

### 4.6 Verify build

After importing all services, run `xcodebuild` to confirm everything compiles. Fix any missing references or import path issues.

---

## Phase 5: Cowork Integration Layer

Import and extend the MCP/HTTP server infrastructure. Build the new content ingestion pipeline.

### 5.1 HTTP server (import + extend)

Copy `CopilotHTTPServer.swift`.

**Add new endpoints:**
- `GET /unprocessed-sessions` — Returns sessions with `redaction_confirmed.json` but no `clinical_notes.json` (for `/process-sessions` skill)
- `POST /notes` — Receives clinical notes JSON from Cowork, validates, triggers ingestion
- `POST /feedback` — Receives feedback JSON, validates, triggers ingestion
- `POST /rolling-summary` — Receives rolling summary text, writes to client folder
- `POST /report` — Receives report JSON, writes to `reports/` folder, triggers ingestion
- `GET /client-profile/{initials}` — Returns `client_profile.json` content
- `GET /clients` — Returns `index.json` content
- `GET /sessions/{initials}` — Returns `client_index.json` content
- `GET /document/{initials}/{path}` — Returns document file content (path-traversal protected)

**Modify existing endpoints:**
- Standby mode endpoints (`/health`, `/clients`, `/client-profile`) work without session token
- Session-scoped endpoints still require token

**Reference:** Cowork integration spec (full tool definitions, parameters, return schemas)

### 5.2 MCP server (extend)

Update `redactor_mcp_server.py` to add new tools:
- `get_unprocessed_sessions` — calls `GET /unprocessed-sessions`
- `write_clinical_notes` — calls `POST /notes`
- `write_feedback` — calls `POST /feedback`
- `write_rolling_summary` — calls `POST /rolling-summary`
- `write_report` — calls `POST /report`
- `get_client_profile` — calls `GET /client-profile/{initials}`
- `list_clients` — calls `GET /clients`
- `list_sessions` — calls `GET /sessions/{initials}`
- `get_document` — calls `GET /document/{initials}/{path}`

Keep existing tools: `health_check`, `start_recording`, `stop_recording`, `pause_recording`, `resume_recording`, `get_session_info`, `get_session_state`, `get_new_chunks`, `write_session_state`, `is_session_complete`

### 5.3 SessionExportService (import + modify)

Copy `SessionExportService.swift`.

**Modifications:**
- Integrate with `WorkspaceManager` for directory creation
- Integrate with `EntityMapSyncService` for entity map loading on session start
- On session start: load persistent entity map from DB before writing initial `entity_map.json`
- On chunk export: use the loaded persistent mappings + new session detections
- Update `writeClaudeMd()` to include all skills and MCP tools per integration spec CLAUDE.md example
- Update `writeSkillFile()` — modify `/live-session` to exit after session ends (no auto-generation)
- Add `writeProcessSessionsSkillFile()` — new `/process-sessions` skill
- Add `writeFeedbackSkillFile()` — standalone `/feedback` skill
- Add `writeReportSkillFile()` — `/report` skill
- Add `writePreSessionSkillFile()` — `/pre-session` skill
- Add `writeCaseloadSkillFile()` — `/caseload` skill
- Keep existing `writeClinicalNotesSkillFile()` — adapt for standalone use

**Reference:** Cowork integration spec (SKILL.md section, CLAUDE.md example)

### 5.4 ContentIngestionService (new)

Create `ContentIngestionService.swift`:
- Watches for Cowork-generated files (triggered by HTTP server receiving writes, not file system polling)
- **Clinical notes ingestion:** Parse `clinical_notes.json` → create `documents` record → update `sessions.notes_generated = 1` → update `sessions.processing_status = 'processed'` → update `client_index.json` → post notification for UI refresh
- **Feedback ingestion:** Parse `feedback.json` → extract scores into `feedback_scores` columns → create `documents` record for narrative → update `sessions.feedback_generated = 1` → update `client_index.json` → update `practitioner_metrics`
- **Report ingestion:** Parse report JSON → create `documents` record → update `client_index.json`
- **Rolling summary:** No DB ingestion needed (file is canonical). Update `documents` table entry if one exists.
- Validate content is redacted (contains substitution tokens, no obvious real names)

**Reference:** Cowork integration spec (Content Ingestion section, ingestion by content type table)

### 5.5 Chunk rewriting after redaction review

Create logic in `WorkspaceManager` (or `SessionExportService`):
- After therapist confirms redaction review, re-read all `chunk_*.json` files for the session
- Apply corrected entity mappings (simple string replacement: old code → new code, or original text → correct code)
- Write corrected chunks back to the same files
- Write `redaction_confirmed.json` with entity stats
- Update `sessions.processing_status = 'redacted'`

**Reference:** File structure doc (redaction_confirmed.json schema), Design doc (Phase 2 — Redaction Review)

---

## Phase 6: App Shell and Navigation

Build the app entry point and navigation structure.

### 6.1 App entry point

Create `RedactorApp.swift`:
- App lifecycle management
- On launch: ensure workspace, start HTTP server in standby, write MCP config
- Initialise DatabaseManager, WorkspaceManager, IndexManager, ClaudeCodeService
- Check for expired transcripts → show forced-choice modal
- Check for discharged clients past 30 days → execute cascade deletion

### 6.2 Onboarding flow

Create `OnboardingView.swift`:
- Step 1: Enter clinician name and title → write to `clinician` table
- Step 2: Grant microphone permission
- Step 3: Claude Code installation — app calls `ClaudeCodeService.isAvailable()`. If not installed:
  - Show install guide with one-click "Install Now" button (runs `brew install --cask claude-code` via Process, shows progress bar) OR copy-paste terminal command
  - After install: clinician runs `claude` once in terminal to authenticate via browser (one-time)
  - App re-checks `isAvailable()` and confirms success
- Step 4: Health check — app spawns `claude -p "hello" --output-format json` to verify CLI works, then tests MCP connection via `health_check` tool
- On completion: flag onboarding complete in UserDefaults

**Reference:** Design doc Section 2 (AI Integration), AI integration spec (Claude Code Setup Instructions)

### 6.3 Main navigation

Two-level navigation:
- **Caseload view** (client list) — list of active clients with last session date, session count, status indicators for pending actions
- **Client workspace** — client detail, session history, document library, feedback metrics

Use NavigationSplitView (macOS sidebar pattern).

### 6.4 Settings

Import and adapt `RecordingSettingsView.swift` for transcription model, audio device, echo cancellation, diarization settings. Add database/workspace settings if needed.

---

## Phase 7: Client Management

### 7.1 Client CRUD ✅

Create views and logic for:
- **Create client:** Name, initials (auto-suggest from name, check uniqueness), title, pronouns, DOB, session type default, duration default → write to DB → create workspace folders → write `client_profile.json` → create pre-seeded entity mappings (CLIENT_A + THERAPIST_A) → update `index.json`
- **Edit client:** Update name, pronouns, defaults → update DB → update `client_profile.json` → update `index.json`
- **Discharge client:** Set status, discharge_date → notification about 30-day deletion → update `index.json` (remove entry)
- **Deferred:** CMS identifier field in create/edit form (field exists in model/DB, UI not yet exposed)

### 7.2 Client workspace view ✅ (partial)

Create `ClientWorkspaceView.swift`:
- ✅ Client demographics header (real names from DB) with edit/discharge
- ✅ Session history list with processing status indicators (colour-coded per schema doc table)
- ✅ Document library (notes, feedback, reports, external docs) with type grouping
- **Deferred to Phase 10.3:** Feedback metrics tab (longitudinal chart of scores across sessions)
- **Deferred to Phase 9:** Action cards for redaction review launch:
  - "Review Redaction" (amber, when sessions at `ended` or `pending_redaction`)
  - "Ready to Process" (blue, when sessions at `redacted` — directs to Claude Code)
  - "View Notes" / "View Feedback" (green, when `processed`)

---

## Phase 8: Recording Flow

Wire up the imported services into the new app's navigation and data layer.

### 8.1 Import recording UI

Copy from `RedactorLite/Recording/`:
- `RecordingWindowView.swift`
- `RecordingWindowController.swift`
- `SessionSetupPanel.swift`
- `LiveTranscriptPanel.swift`
- `SessionEntityPanel.swift`
- `CopilotDashboardView.swift`
- `ClinicalNotesView.swift`
- `FirstTimeSetupView.swift`

Adapt to use new data layer:
- Session setup pulls defaults from `Client` record (session type, duration)
- On recording start: create `Session` record in DB with `processing_status = 'active'`
- On recording stop: update to `processing_status = 'ended'`, write `session_complete.json`
- Entity panel reads from in-memory `EntityMapping` (loaded from persistent library on start)

### 8.2 Live session lifecycle

Wire the full pipeline:
1. User starts recording from client workspace (or Cowork triggers via MCP)
2. `SessionManager` starts audio capture + transcription
3. `LiveRedactor` redacts segments in real-time using persistent entity library
4. `SessionExportService` writes redacted chunks to workspace
5. Dashboard displays metrics from `session_state.json` (written by Cowork)
6. Session ends → `session_complete.json` written → Cowork exits
7. `Session.processing_status` → `ended`

### 8.3 Dashboard integration

Import `CopilotDashboardView.swift`. It already:
- Reads `session_state.json` on a timer
- Displays arc gauges, coaching comment, therapist request buttons
- Substitutes entity codes with real names from `entity_map.json`
- Shows status indicator for Cowork connection

Verify it works with the new workspace paths.

### 8.4 Session auto-population from client ✅ (was deferred, completing now)

**Critical fix:** The recording setup must pre-fill from the selected client's data:
- Client initials (auto-set, not manually entered — prevents orphaned sessions)
- Default session type (from client record)
- Default duration (from client record)
- Only ask for: session goals and multi-speaker toggle

Pass the Client object through RecordingWindowController → RecordingWindowView → SessionSetupPanel.

### 8.5 Save detected entities to DB during recording ✅ (was missing, completing now)

Entities detected by LiveRedactor during recording are in-memory only (LiveSession.detectedEntities). They're lost on app restart and unavailable in the review view. Fix: save session-scoped entity mappings to DB when recording stops, so the review can load them.

### 8.6 Recording UI design migration (deferred to Phase 14)

The imported v2 recording UI uses the old design system. Migrate to Minimal Frost:
- Sora font, slate palette, glass panels, gradient background
- Claude Code warning banner in Minimal Frost visual language
- Simplified recording flow

### 8.7 URL scheme handler (deferred — add when needed)

Register URL scheme for external app triggering. Not needed for core workflow.

---

## Phase 9: Redaction Review

Build the post-session redaction review UI — the gate between recording and processing.

### 9.1 Redaction review view

Create `RedactionReviewView.swift`:
- Shows full transcript (from `transcript_segments` in DB) with detected entities highlighted
- Entity sidebar listing all detected entities grouped by type
- For each entity: original text, assigned code, confidence, source
- Actions per entity: confirm, exclude, change type, merge with another entity
- Bulk actions: confirm all, auto-merge duplicates
- "Add entity" — manually mark text as PII

Draw from existing `RedactPhaseState.swift` for entity management logic (overlap resolution, deduplication). Import it and adapt.

### 9.2 Redaction confirmation flow

When therapist confirms:
1. Promoted entities: copy from `persistence_scope = 'session'` to `'client'` in DB
2. Sync entity map: `EntityMapSyncService` writes updated `entity_map.json`
3. Rewrite chunks: `WorkspaceManager` re-applies corrected entity mappings to all `chunk_*.json` files
4. Write `redaction_confirmed.json` to session folder (with entity stats)
5. Update `Session.processing_status` → `redacted`
6. UI shows "Ready to process — go to Cowork and type `/process-sessions`"

### 9.3 Batch review

The caseload view should highlight clients with sessions awaiting review. The therapist can review multiple sessions in sequence. Each confirmation is independent.

### 9.4 Action cards in ClientWorkspaceView (deferred from Phase 7) — PARTIAL ✅

- ✅ "Review Redaction" button (amber) — opens RedactionReviewView
- ✅ "View" button — reopens transcript for reviewed/processed sessions
- ✅ "Ready" indicator (blue) — shows on redacted sessions
- **Deferred to Phase 10:** "View Notes" / "View Feedback" links (need document viewer first)

### 9.5 Save live-detected entities to DB ✅ (completing now)

Entities detected during recording by LiveRedactor are saved to `entity_mappings` table with `persistence_scope = 'session'` when recording stops. This allows the review view to display them alongside the persistent library entities.

Without this, the review view only shows persistent library entities — new names detected during THIS recording would be invisible.

---

## Phase 10: Document Viewer and Export

### 10.1 Document viewer

Create `DocumentViewerView.swift`:
- Reads document file from workspace (path from `documents` table)
- Applies entity substitution (codes → real names from `entity_mappings` table) at display time
- Renders markdown formatting
- Section-level copy to clipboard (with real names)
- "Copy All" button
- Edit capability for therapist amendments (writes back to file, updates `documents.updated_at`)

### 10.2 Clinical notes view

Import `ClinicalNotesView.swift` — already handles the 3-section format with entity substitution and copy actions. Adapt to read from the document path in the `documents` table rather than a hardcoded session folder.

### 10.3 Feedback display

Create `FeedbackDetailView.swift`:
- Signal labels: 4-5 green (Strength), 3 amber (On Track), 1-2 red (Watch Point), NULL grey (N/A)
- Display all 11 constructs + 4 derived scores
- Show narrative text with entity substitution

Create `FeedbackHistoryView.swift`:
- Longitudinal chart of scores across sessions for a client
- Show trends, highlight changes

### 10.3a Feedback metrics tab in ClientWorkspaceView (deferred from Phase 7)

Add "Feedback" tab to ClientWorkspaceView's segmented picker (alongside Sessions and Documents). Shows FeedbackHistoryView with longitudinal chart for the selected client.

### 10.4 Export

All document views include "Copy to Clipboard" with real names substituted. This is the primary export path to CMS. Entity substitution happens in memory at copy time — never written to storage.

### 10.5 "View Notes" / "View Feedback" links in SessionHistoryView (deferred from Phase 9.4)

Wire the existing notes/feedback icons in SessionHistoryView to open the document viewer when clicked. Currently they're display-only indicators.

---

## Phase 11: Work Sessions (Rough Notes and External Documents)

### 11.1 Rough notes flow

Rough notes go directly to Cowork for transformation — they don't go through the app's redaction pipeline first.

Flow:
1. User goes to Cowork → `/clinical-notes {initials}` → pastes rough notes
2. Cowork applies entity codes from client profile context
3. Cowork generates structured notes → writes via `write_clinical_notes`
4. App ingests via `ContentIngestionService`
5. App displays with entity substitution

The app's role is minimal here — just ingestion and display.

### 11.2 External document upload

Background documents (referral letters, assessments) are uploaded via the app for reference.

Create `DocumentUploadView.swift`:
1. Select client
2. Upload/paste document text
3. Redaction scan runs (same NER pipeline as sessions)
4. Show redaction review (can reuse `RedactionReviewView` in a simpler mode)
5. Therapist confirms
6. `original_text` cleared from `source_documents` record
7. Redacted document written to `Sessions/{initials}/external/`
8. Create `documents` record
9. Update `client_index.json`
10. Available to Cowork via `get_document` MCP tool for report generation

---

## Phase 12: SKILL.md Development

Write the prompt content for each Cowork skill. This is prompt engineering work referencing the existing live-session SKILL.md as the template.

### 12.1 Update `/live-session` SKILL.md

Modify `writeSkillFile()`:
- Remove the Step 5 (clinical notes generation) — this now happens in `/process-sessions`
- When `is_session_complete()` returns true: do final analysis, write final state, tell user session is complete, **exit skill**
- Keep all analysis rules (utterance classification, agenda tracking, themes, people, rupture, risk, coaching comments) unchanged

### 12.2 New `/process-sessions` SKILL.md

Create `writeProcessSessionsSkillFile()`:
- Call `get_unprocessed_sessions()` to find sessions ready for processing
- If none: tell user all sessions are up to date
- For each session:
  1. Read `session_info.json` via `get_session_info`
  2. Read `client_profile.json` via `get_client_profile`
  3. Read all chunks via `get_new_chunks(since_index=0)`
  4. Read `rolling_summary.md` via `get_document` (for context)
  5. Read previous `feedback.json` via `get_document` (for longitudinal comparison)
  6. Generate clinical notes (3 sections) → `write_clinical_notes`
  7. Generate feedback (7-pass analysis, building on live session data) → `write_feedback`
  8. Update rolling summary → `write_rolling_summary`
  9. Move to next session
- Clinical notes rules: use existing rules from Transcript Notes Transformation doc
- Feedback rules: 7-pass analysis as defined in design doc Section 9

### 12.3 Update `/clinical-notes` SKILL.md

Adapt existing `writeClinicalNotesSkillFile()`:
- Support rough notes input (user pastes directly into Cowork)
- Support regeneration from existing chunks
- Same output format (3 sections)

### 12.4 New `/feedback` SKILL.md

Standalone feedback generation for a specific session:
- Read all chunks for specified session
- Run 7-pass analysis
- Write `feedback.json`

### 12.5 New `/report` SKILL.md

- Read `report_request.json` from client folder
- If not found: ask user to prepare report in app first
- Read each source document via `get_document`
- Read `client_profile.json` for context
- Read template instructions from the request
- Generate report
- Write via `write_report`

### 12.6 New `/pre-session` SKILL.md

- Ask for client initials
- Read `rolling_summary.md`
- Read most recent `clinical_notes.json`
- Read most recent `feedback.json`
- Generate concise key-points brief
- Display in Cowork (not stored)

### 12.7 New `/caseload` SKILL.md

- Read `index.json` for client list
- For each active client: read `rolling_summary.md`
- Read recent `feedback.json` files across clients
- Generate caseload overview or aggregate practitioner metrics
- Display in Cowork (not stored)

### 12.8 Update `CLAUDE.md`

Update `writeClaudeMd()` to match the full CLAUDE.md example in the Cowork integration spec:
- All 7 skills listed with descriptions
- All MCP tools listed with parameters
- Workspace structure description
- Entity code rules
- Index file navigation instructions
- Clinician name/title from DB

---

## Phase 13: Retention and Cleanup

### 13.1 Transcript expiration

On app launch and periodically:
- Query sessions where `transcript_expires_at < now` and `transcript_segments` exist
- Show forced-choice modal (cannot dismiss):
  - "Delete transcript" → delete `transcript_segments` for session
  - "Generate notes first" → direct to Cowork `/process-sessions` (if not already processed)
- Set `transcript_expires_at` when `processing_status → redacted` (now + 14 days)

### 13.2 Discharge cleanup

On app launch:
- Query clients where `status = 'discharged'` and `discharge_date + 30 days < now`
- Execute cascade deletion per schema doc:
  - Delete all DB records (feedback_scores, documents, transcript_segments, audio_chunks, entity_positions, entities, entity_mappings, redacted_persons, source_documents, sessions, client)
  - Delete workspace folder `Sessions/{initials}/`
  - Delete private folder `Private/{initials}/`
  - Update `index.json` (remove client entry)
- Do NOT delete `practitioner_metrics`

### 13.3 Session cleanup

After session is fully processed:
- Delete transient files: `session_state.json`, `.server_token`
- Retain: `session_complete.json`, `redaction_confirmed.json` (status markers), `chunk_*.json` (for re-analysis), `clinical_notes.json`, `feedback.json`

### 13.4 Session goals cleanup

When `processing_status → processed`:
- Clear `session_goals` field (transitory — per design decision)

### 13.5 Audio cleanup

When session ends and transcription is complete:
- Delete all `audio_chunks` records and files
- Audio is never needed after transcript exists

---

## Phase 14: Testing and Polish

### 14.1 End-to-end session flow

Test the full pipeline:
1. Create client → verify workspace folders, entity_map.json, client_profile.json, index files
2. Start recording (from app or via Cowork MCP) → verify audio capture, transcription, live redaction, chunk export
3. Cowork `/live-session` → verify dashboard updates, coaching comments, analysis
4. Stop recording → verify `session_complete.json`, status → ended
5. Redaction review → verify entity correction, chunk rewriting, `redaction_confirmed.json`
6. Cowork `/process-sessions` → verify notes + feedback generation, ingestion into DB
7. View notes/feedback in app → verify entity substitution, formatting, copy
8. Verify transcript expiration modal
9. Verify discharge cascade

### 14.2 Work session flow

Test:
1. Rough notes via Cowork `/clinical-notes` → verify ingestion
2. External document upload → verify redaction, storage, availability to Cowork
3. Report generation via `/report` → verify request file, generation, ingestion

### 14.3 Edge cases

- Back-to-back sessions (multiple sessions for different clients in sequence)
- Client initials collision (JB, JB2)
- Session with no entities detected
- Cowork connection failure during live session (dashboard holds last state)
- App restart mid-session (token recovery)

---

## File Import Summary

| Category | Files | Import as-is | Modify |
|----------|-------|-------------|--------|
| Audio/Recording | 5 | 5 | 0 |
| Transcription | 4 | 4 | 0 |
| Speaker Diarization | 1 | 1 | 0 |
| Redaction Pipeline | 27 | 27 | 0 |
| MCP/Cowork | 3 | 1 | 2 |
| Recording UI | 9 | 9 | 0 |
| Models | 15 | 15 | 0 |
| Resources | 9 | 9 | 0 |
| Utilities | 12 | 12 | 0 |
| **Total imported** | **85** | **83** | **2** |

**New code to write:**
- Database layer (DatabaseManager, migrations, repositories) — ~10 files
- Workspace services (WorkspaceManager, IndexManager, EntityMapSyncService, ContentIngestionService) — ~4 files
- App shell and navigation — ~3 files
- Client management views — ~3 files
- Redaction review view — ~2 files
- Document viewer and export — ~4 files
- Work session views — ~2 files
- SKILL.md generation methods — 5 new methods in SessionExportService
- HTTP server extensions — additions to CopilotHTTPServer
- MCP server extensions — additions to redactor_mcp_server.py

**Estimated new files: ~30 | Imported files: ~85**
