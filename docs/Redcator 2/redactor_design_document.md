# Redactor — Comprehensive Design Document
## Version 2.0 — Cowork Architecture

---

## 1. Product Vision and Positioning

### What Redactor Is
Redactor is a clinical intelligence and transformation tool for individual therapists and psychologists. It takes raw clinical material — session recordings, rough notes, uploaded documents — and transforms it into useful outputs using AI: session notes, client-facing notes, formal reports, practitioner feedback, and longitudinal clinical intelligence.

### What Redactor Is Not
Redactor is not a clinical management system (CMS). It does not replace PowerDiary, Halaxy, or any other practice management tool. It does not handle invoicing, scheduling, or administrative functions. It is not the permanent source of truth for clinical records.

### The Relationship with a CMS
Redactor sits alongside a CMS as a clinical intelligence layer. The CMS is the system of record. Redactor is the system of insight. Clinicians generate outputs in Redactor and copy or export them to their CMS. Integration points are made as frictionless as possible — at minimum, easy copy to clipboard. A PowerDiary API integration is a future consideration but not in scope for the initial build.

### Target User
Individual clinicians — psychologists, therapists, coaches, supervisors — working in private practice on macOS. Single user per installation. No multi-user or practice-level functionality in v1.

### Commercial Positioning
Built initially for 3 Big Things Limited's clinical team. Designed with commercial potential in mind. Architecture decisions should not foreclose future licensing or multi-practice deployment, but complexity for those scenarios is not added upfront.

---

## 2. Platform and Technology Decisions

### Platform: macOS only (Swift/SwiftUI)
**Decision:** Stay with Swift for the initial build. The existing Redactor codebase is Swift and the foundation is solid.
**Rationale:** Rebuilding cross-platform adds complexity before the product is validated. Mac-only limits commercial ceiling but is the right call for v1.
**Future consideration:** Flutter or web app for cross-platform. Architecture should keep core logic separable from UI to enable future porting.

### AI Integration: Claude Cowork via MCP
**Decision:** Redactor uses Claude Cowork (the agentic mode in Anthropic's Claude Desktop app) as its AI layer. The app communicates with Cowork via an MCP server (stdio between Cowork and a Python MCP proxy, which forwards over HTTP to the app's internal server) and SKILL.md workflow definitions. The app does not call the Anthropic API directly.
**Rationale:** Direct API integration is the ideal architecture but is currently blocked by privacy requirements — clinical content (even redacted) cannot be transmitted to third-party API servers under current policy. Cowork provides the same Claude model with local data residency. The existing MCP infrastructure (HTTP server, MCP tools, SKILL.md generation) is already built and proven for live session analysis.
**Initiation constraint:** Cowork cannot be triggered programmatically from an external application. All AI workflows must be initiated by the user within Cowork (e.g., typing a slash command). Once initiated, workflows run autonomously via polling loops and MCP tools. This is a fundamental constraint of the Cowork architecture, not a temporary limitation.
**Future migration:** When privacy constraints are resolved, the app can migrate to direct API calls. The data layer, document storage, and UI work the same regardless of how AI content arrives. However, SKILL.md workflows contain Cowork-specific logic (polling loops, session state management, interaction patterns) that would need significant rewriting as API system prompts — this is not a simple swap.

### Local AI for Redaction: Apple NLP + MLX
**Decision:** Retain existing redaction pipeline using Apple NaturalLanguage, XLM-RoBERTa CoreML model, and MLX Swift for on-device inference.
**Rationale:** Redaction must happen locally before any content is visible to the AI layer. This is already built and working.

### Database: SQLCipher
**Decision:** Single SQLCipher encrypted database per installation.
**Rationale:** SQLite with AES-256 encryption. The encryption key lives in the macOS Keychain. Industry standard for clinical applications requiring local encrypted storage. All structured data lives here. Cowork cannot query the database — it interacts with the app via MCP tools that read/write files in the workspace.

### File Storage: Documents on disk, indexed by database
**Decision:** Generated documents stored as markdown files in the workspace directory structure. The SQLCipher database stores paths and index metadata, not file content.
**Rationale:** Documents are whole-file objects better suited to file storage than database BLOBs. Markdown allows basic formatting useful for clinical notes. The workspace directory doubles as the file interface between the app and Cowork.

### Workspace: Shared file interface between app and Cowork
**Decision:** A workspace directory at `~/Library/Application Support/Redactor/Workspace/` serves as the file-based communication layer between the app and Cowork. It contains redacted client data that Cowork can access via MCP tools, and receives generated content that the app ingests.
**Rationale:** Cowork operates on files in a working directory. The workspace provides the structured file system Cowork needs while keeping real names and the database internal to the app.

---

## 3. Privacy and Security Architecture

### Core Privacy Principle
Redaction is the gateway. Unredacted content never enters permanent storage, never enters the workspace, and is never visible to the AI layer. This is enforced architecturally, not by policy.

### Security Stack (layered)
1. **SQLCipher** — AES-256 encrypted database. Encryption key in Keychain.
2. **macOS Keychain** — Hardware-backed storage for database encryption key.
3. **Apple Data Protection API** — Files inaccessible when Mac is locked.
4. **Biometric authentication** — Touch ID or password required to open Redactor.
5. **App sandbox** — OS-level isolation from other applications.
6. **Screenshot protection** — Sensitive views explicitly blanked during app switching.

### Re-identification Rule
Stored content is always redacted. Substitution tokens ([CLIENT_A], [PERSON_B] etc.) are present in all stored files and database records. Re-identification happens only at the moment of display on screen, using the entity_mappings table to substitute tokens back to real names at render time. Nothing re-identified is ever written to storage.

### Cowork Privacy Model
Everything Cowork sees is redacted. The workspace contains only substitution tokens — never real names. Entity maps with real names live in `Private/`, which is never registered with the MCP server and has no MCP tool that can reach it. Cowork's own data handling (API calls to Anthropic) uses redacted content only.

### Temp Directory Separation
Unredacted material lives in a separate temp directory (~/Library/Application Support/Redactor/temp/) that is:
- Completely separate from the workspace and data directory
- Never registered with the MCP server
- Never accessible via any MCP tool
- Cleared immediately on redaction confirmation or session abandonment

### Client Identification
The app stores full client identity (name, DOB, demographics) in the encrypted database. Cowork and the workspace use only client initials (e.g., `JB`) as folder names and identifiers. The therapist can recognise clients on sight from initials. For collisions, a numeric suffix is added (e.g., `JB2`). The mapping between initials and full identity exists only in the database.

---

## 4. Redaction Architecture

### Three-Layer Redaction Model

**Layer 1 — Live session scan (during recording)**
Real-time redaction of transcript chunks as they arrive. Uses the client's persistent redaction library as primary layer. Secondary scan for new terms not in the library. Temporary — chunk-level maps are discarded at session end after merging new terms into the persistent library.

**Layer 2 — Post-session full scan (after recording ends)**
Full redaction of the complete assembled transcript using Apple NLP + local LLM. More accurate than chunk-level scanning. Identifies new terms not caught live. Therapist reviews and confirms new terms via a post-session review UI. Confirmed terms are promoted to the client's persistent redaction library.

**Layer 3 — Document ingestion scan (for uploaded documents)**
Same process as post-session scan applied to uploaded rough notes and external documents. Therapist confirms new terms. Original unredacted text is deleted from temp directory once redaction is confirmed.

### Persistent Client Redaction Library
**Key architectural decision:** Entity mappings persist at client level across all sessions. This is the most significant change from the original Redactor architecture which scoped mappings to a single session or workflow.

When a new session begins for an existing client, the persistent library is loaded first. The session builds on it. After session, confirmed new terms are merged into the library. Over time the library becomes increasingly refined, reducing the post-session review burden.

The persistent library lives in `Private/{initials}/entity_map.json` and in the `entity_mappings` database table (with `persistence_scope = 'client'`). The database is the authoritative store. Sync direction:
- **Session start:** Database → file. Client-scoped mappings are exported to `entity_map.json` and loaded into the in-memory `EntityMapping`.
- **During session:** New detections are added to the in-memory mapping and written to the file as a working copy.
- **Post-session review:** Therapist reviews new entities. Confirmed entities are promoted: copied from `persistence_scope = 'session'` to `persistence_scope = 'client'` in the database (session record preserved).
- **Session end:** Promoted mappings are written to both the database and `entity_map.json`.
- **If file and database diverge:** Database wins. The file is regenerated from database on next session start.

### Pre-seeded Entity Mappings
Two entities are automatically added to every client's redaction library at client creation — before any session or redaction occurs:

1. **Client name** → `[CLIENT_A]` (with all variants: `[CLIENT_A_FIRST]`, `[CLIENT_A_LAST]`, `[CLIENT_A_FORMAL]`). Sourced from the `clients` table (`full_legal_name`, `preferred_name`, `title`). The client is always `CLIENT_A` — never assigned a different letter.

2. **Therapist name** → `[THERAPIST_A]` (with variants). Sourced from the `clinician` table (`full_name`, `title`), which is set once during onboarding and applies globally. The therapist is always `THERAPIST_A` across all clients. When a new client is created, the app automatically copies the therapist mapping into that client's redaction library. This ensures the clinician's own name is always redacted from transcripts and documents.

These pre-seeded mappings are created with `persistence_scope = 'client'` and `source = 'system'`. The therapist mapping originates from the `clinician` table (set once at onboarding) and is copied into each client's library on client creation. They cannot be excluded or deleted by the user. All subsequent person entities detected during sessions are assigned codes starting from `PERSON_B` (since A is taken by the client).

### Entity Types
person_client, person_other, date, location, organization, identifier, contact, numeric_all.

### Person Variant System
Persons get special treatment. Each person entity has a redacted_persons record storing title, full_name, first_name, last_name, middle_name. Seven derived variant codes are computed (not stored): [PERSON_A] full name, [PERSON_A_FIRST], [PERSON_A_LAST], [PERSON_A_FORMAL] (Title Last), and three further variants per current implementation. This ensures consistency across all forms a name might appear.

### First-Write-Wins
Entity mappings enforce that once a normalized text has a mapping within a client scope, it cannot be overwritten. This preserves the redaction decision made at review time.

### Re-identification at Display
The entity_mappings table is never exposed to Cowork. Re-identification is a Redactor-internal operation triggered only when displaying content on screen. The clinician sees real names in the app UI. The stored files always contain tokens.

---

## 5. Data Architecture

### Database
Single SQLCipher database: ~/Library/Application Support/Redactor/redactor.db

**Tables and their purpose:**

**clinician** — One record per installation. Full name and title used in generated outputs.

**clients** — Core client record. Fields: id (UUID), initials (unique, used for workspace folders), cms_identifier, title (Mr/Mrs/Ms/Dr etc.), full_legal_name, preferred_name, pronouns, date_of_birth, onboarding_date, status (active/discharged), discharge_date, default_session_type, default_session_type_desc, default_duration_minutes.
Note: preferred_name is used by the AI in all outputs. initials is the workspace identifier and Cowork-visible label.

**sessions** — Session records. Fields include: input_type (recorded/rough_notes), session_type (defaults from client but overridable), processing_status (active/ended/pending_redaction/redacted/processed), notes_generated (boolean), feedback_generated (boolean), transcript_expires_at. See schema doc for full processing status flow and UI indicators.

**audio_chunks** — Temp records for audio file references. All deleted when session ends.

**transcript_segments** — Session transcript. Deleted when transcript_expires_at is reached (2 weeks post-redaction) via forced-choice modal.

**entities** — All PII entities detected across all sessions and documents for a client. Client-scoped and persistent.

**entity_positions** — Character positions of entities within documents.

**entity_mappings** — Source of truth for original→replacement mappings. Scoped to session, document, or client (persistent). Unique constraint on (client_id, persistence_scope, original_text_normalized).

**redacted_persons** — Person entity detail for variant code derivation. Includes title field.

**source_documents** — Uploaded documents for work sessions. original_text cleared once redaction confirmed.

**documents** — Index of all generated files. Stores path, document_type, index_summary.

**feedback_scores** — 11 scoreable constructs plus 4 derived scores per session. All stored as individual INTEGER columns (not JSON) for queryability. NULL = N/A. Signal labels (Strength/On track/Watch point) applied at display time.

**practitioner_metrics** — Aggregate anonymised metrics at clinician level. No client FK. Persists indefinitely after client discharge.

**report_templates** — App-level. System defaults ship with app. Custom templates belong to individual installation.

### Feedback Score Fields
listening_quality, empathy, warmth, rupture_repair, client_engagement, partnership, goal_alignment, session_arc, persuasiveness, hope, cultivating_change_talk, softening_sustain_talk (all INTEGER 1-5 or NULL), relational_global, technical_global, reflection_question_ratio, complex_reflections_pct (all REAL).

### File Structure
```
~/Library/Application Support/Redactor/
├── redactor.db                    (SQLCipher database)
├── temp/                          (unredacted material, never visible to Cowork)
│   └── [session-uuid]-*.txt
└── Workspace/                     (shared interface with Cowork)
    ├── Sessions/                  (redacted client data, Cowork reads and writes)
    │   ├── index.json             (app writes — root index of all clients)
    │   └── [initials]/
    │       ├── client_profile.json    (app writes for Cowork context)
    │       ├── client_index.json      (app writes — sessions and documents index)
    │       ├── rolling_summary.md     (Cowork updates after each session)
    │       ├── reports/               (Cowork-generated reports, client-level)
    │       ├── external/              (uploaded background documents, redacted)
    │       ├── report_request.json    (app writes when clinician requests a report)
    │       └── [date_time]/           (session folders)
    │           ├── session_info.json
    │           ├── chunk_*.json
    │           ├── session_state.json
    │           ├── session_complete.json
    │           ├── clinical_notes.json    (Cowork writes)
    │           ├── feedback.json          (Cowork writes)
    │           └── .server_token
    ├── Private/                   (app only, Cowork cannot access)
    │   └── [initials]/
    │       └── entity_map.json    (real names → codes)
    └── CoWork Files/              (user opens this folder in Cowork)
        ├── CLAUDE.md              (directs Cowork to use skills)
        └── .claude/skills/        (auto-generated by app)
            ├── live-session/SKILL.md
            ├── process-sessions/SKILL.md
            ├── clinical-notes/SKILL.md
            ├── feedback/SKILL.md
            ├── report/SKILL.md
            ├── pre-session/SKILL.md
            └── caseload/SKILL.md
```

Document files generated by Cowork are markdown (.md) or JSON. Named by document type and session date. Always contain redacted content only.

### Index Files
**index.json** (root) — Written by the app at `Sessions/index.json`. Lists all clients with aggregate metadata (initials, session counts, last session date). No clinical content, no real names. Updated when clients are created/discharged and when sessions complete. Cowork reads this at the start of cross-client tasks.

**client_index.json** — Written by the app at `Sessions/{initials}/client_index.json`. Lists all sessions and generated documents for a client with one-sentence summaries. Updated when sessions complete, when documents are ingested, and when documents are deleted. Cowork reads this to navigate a client's history and decide which documents to fetch.

**client_profile.json** — Written by the app when a client is created or updated. Contains non-identifying metadata Cowork needs for context: initials, session type default, pronouns, session count, last session date. No real names. No DOB.

**rolling_summary.md** — Updated by Cowork after each session. Contains a running clinical summary in redacted form. The app reads this to display session-over-session context to the clinician (with entity substitution for display).

---

## 6. Cowork Integration Architecture

### Communication Model
The app and Cowork communicate via a three-layer interface:

1. **MCP Server** (`redactor_mcp_server.py`) — Python process providing MCP tools. Cowork calls these tools during skill execution. The MCP server forwards requests to the app's HTTP server.

2. **HTTP Server** (`CopilotHTTPServer.swift`) — Runs inside the app on port 8787. Receives MCP tool requests, executes them against the workspace file system, and returns results. Handles auth via session tokens.

3. **SKILL.md Files** — Auto-generated workflow definitions that Cowork discovers as slash commands. Each skill defines a complete workflow with MCP tool sequences, analysis rules, and output formats. The app generates these on launch via `SessionExportService.writeSkillFile()`.

### MCP Tools

**Recording control:**
- `start_recording` — Start audio recording and transcription
- `stop_recording` — Stop recording, triggers session_complete marker
- `pause_recording` / `resume_recording` — Pause/resume during session

**Session data (live):**
- `get_new_chunks(since_index)` — Get redacted transcript chunks since index N. Returns chunks + latest_index
- `get_session_info` — Session metadata (type, date, goals, client initials)
- `get_session_state` — Current analysis state (metrics, themes, people, risk)
- `write_session_state(state_json)` — Push updated analysis to dashboard
- `is_session_complete` — Check if recording has ended

**Content generation (post-session and standalone):**
- `write_clinical_notes(notes_json)` — Write clinical notes to session folder
- `write_feedback(feedback_json)` — Write feedback scores and narrative to session folder
- `write_rolling_summary(summary_text)` — Update client's rolling summary
- `write_report(report_json)` — Write report output to session folder

**Client context:**
- `get_client_profile(initials)` — Read client_profile.json for context
- `list_clients` — List all client folders with basic metadata
- `list_sessions(initials)` — List all sessions for a client
- `get_document(initials, path)` — Read a specific document from client's folder
- `health_check` — Verify connection to app

### Client Scoping
Each MCP tool that accesses client data takes an `initials` parameter. The HTTP server validates that the request only accesses data within that client's folder. For live sessions, the session token provides additional scoping to the active session folder.

For cross-client tasks (caseload summary), the `list_clients` tool returns all client folders and the skill reads across them intentionally.

### SKILL.md Workflows

Each skill is a complete, self-contained workflow definition. The app auto-generates all skills on launch. To modify a workflow, edit the `writeSkillFile()` method in `SessionExportService.swift` — never edit workspace files directly as they are overwritten on launch.

**Skills:**

**`/live-session`** — Live session analysis only. Setup questions → start recording → polling loop (get_new_chunks → analyse → write_session_state → is_session_complete) → session ends → final analysis summary → skill exits. Uses real-time (imperfect) redaction. All output is transient dashboard data — no permanent documents are generated. Session status moves to `ended`.

**`/process-sessions`** — Batch post-session generation. Scans all client folders for sessions with `redaction_confirmed.json` but no `clinical_notes.json`. For each: generates clinical notes, generates feedback (7-pass), updates rolling summary. Processes multiple sessions in one invocation. Uses corrected redaction from the therapist's review. Session status moves to `processed`.

**`/clinical-notes`** — Standalone note generation for a specific session. For regeneration or sessions processed outside the batch flow.

**`/feedback`** — Standalone multi-pass feedback analysis. 7 passes (6 construct passes + synthesis), writes feedback.json with all 11 constructs and narrative.

**`/report`** — Report generation from selected documents. App prepares a `report_request.json` with source document paths and template instructions. Cowork reads and generates.

**`/pre-session`** — Pre-session brief. Reads rolling summary + last session's notes + last feedback for the specified client. Generates concise key-points brief.

**`/caseload`** — Cross-client analysis. Lists all clients, reads rolling summaries and recent feedback, generates aggregate practitioner metrics or caseload overview.

### Data Flow

```
Clinician initiates in Cowork (slash command)
  → Cowork executes SKILL.md workflow
  → Cowork calls MCP tools
  → MCP server forwards to HTTP server
  → App processes request (read/write workspace files)
  → Cowork receives result, continues workflow
  → Cowork writes generated content via MCP tool
  → App detects new content (file watch or notification)
  → App validates and ingests into database
  → App displays to clinician with entity substitution
```

### What Cowork Never Sees
- Real names (entity maps in Private/, never exposed via MCP)
- The database (all structured data accessed through app, not Cowork)
- Unredacted content (temp directory not registered with MCP)
- Full client identity (only initials visible in workspace)

---

## 7. Live Session Architecture

### What Lives in Memory (never persisted)
The live session state is an in-memory structure maintained by Redactor for the duration of the session. Contents:
- client_talk_pct (calculated by app from speaker labels and timestamps)
- engagement_score (composite — app calculates from AI-coded data)
- rq_ratio (AI codes utterances, app accumulates)
- ex_pct (AI codes, app accumulates)
- utterance_counts (Q, SR, CR, EX, O — AI codes per chunk)
- rolling_10min_window metrics
- agenda_items with status (not_discussed/partially_discussed/fully_discussed) and evidence
- themes with phrase counts
- people_and_details
- rupture_indicators
- risk_flags with rationale

This structure is in active development and will expand. JSON-based to allow field additions without schema changes.

### Live vs Post-session Scores
Live session metrics are entirely transient — displayed on dashboard during session, discarded at session end. They are NOT converted to feedback_scores database records. Post-session feedback is a separate multi-pass analysis (automated as part of the /live-session skill) that creates the permanent feedback_scores record.

### Post-Session Pipeline
Live analysis and document generation are **separate concerns** with a redaction review gate between them.

**Why they're split:** Live session analysis uses real-time redaction which is imperfect — names get missed, duplicated, or incorrectly coded. The therapist must review and correct entities before permanent documents are generated. Additionally, clinicians often have back-to-back sessions and cannot review redaction immediately. Keeping `/live-session` short (exits when recording ends) frees Cowork for the next session.

**The pipeline:**

```
/live-session (Cowork)     →  Redaction Review (App)     →  /process-sessions (Cowork)

Recording + live analysis     Therapist reviews entities     Generates notes + feedback
Dashboard metrics             Confirms, corrects, merges     Uses corrected chunks
Coaching comments             New terms → persistent lib     Updates rolling summary
                              App rewrites chunk files
Session ends → skill exits    Writes redaction_confirmed     Session → processed
Status: ended                 Status: redacted               Status: processed
```

**Batch processing:** `/process-sessions` handles all outstanding sessions in one invocation. The clinician can record 5 sessions in the morning, review redaction during lunch, then run `/process-sessions` once to generate everything.

### Speaker Label Handling
Current implementation must handle variant label formats in the speaker matching logic: therapist_1/therapist_2 vs therapist/client.

### Dashboard Status Indicator
A non-intrusive status indicator shows whether live analysis is currently processing, paused, or has lost connection. Holds last known state on failure. Never interrupts the clinician during a session.

### Transcript Chunking
A "chunk" is a batch of consecutive transcript segments exported together. Chunks are created by the app based on time — approximately every 30 seconds of transcribed audio, or when a natural pause occurs. Each chunk contains one or more speaker segments with timestamps. Chunk files are numbered sequentially (`chunk_001.json`, `chunk_002.json`). Cowork polls for new chunks via `get_new_chunks(since_index)`.

### Rolling Summary
Each client has one `rolling_summary.md` file in their workspace folder. It is a running clinical narrative updated by Cowork after each session. The app creates an empty `rolling_summary.md` when the client folder is first created. Cowork overwrites the entire file on each update (not append). The rolling summary should stay concise — if it grows beyond approximately 2000 words, Cowork should summarise it as part of the update.

### Session Initiation
The clinician opens Cowork and types `/live-session` or says "start a session". The skill asks setup questions (client initials, session type, goals, expected duration). Cowork then calls `start_recording` via MCP. From this point the session is fully automated.

---

## 8. Retention and Deletion Model

### Data Retention Hierarchy
| Data | Retention | Deletion trigger |
|------|-----------|-----------------|
| Raw audio / audio_chunks | Until transcription complete | Deleted when session ends and transcription is finished |
| Live session metrics | Session duration | Session ends (memory only) |
| Unredacted transcript (temp) | Until redaction confirmed | Redaction confirmed or abandoned |
| Uploaded docs before redaction (temp) | Until confirmed | Redaction confirmed or abandoned |
| source_documents.original_text | Until redaction confirmed | Cleared on confirmation |
| transcript_segments (DB) | 2 weeks post-redaction | Forced-choice modal at transcript_expires_at |
| Workspace chunk files (chunk_*.json) | Until client discharged | Already redacted — persist with session folder. Needed for Cowork re-analysis |
| Transient session files (.server_token, session_state.json) | Session duration | Deleted after session is fully processed |
| Status markers (session_complete.json, redaction_confirmed.json) | Until client discharged | Retained — used by Cowork to determine session state |
| Client data and documents | Discharge + 30 days | Entire client folder and records deleted |
| Feedback scores | Discharge + 30 days | Deleted with client |
| Practitioner metrics | Indefinitely | Never deleted (no client FK, fully anonymous) |
| Rolling summary (workspace) | Until client discharged | Deleted with client workspace folder |
| Entity map (Private/) | Until client discharged | Deleted with client |

### Workspace Cleanup
After a session is fully processed (notes and feedback generated, ingested by app):
- `session_state.json` is deleted (transient dashboard data)
- `.server_token` is deleted (transient auth)
- `session_complete.json` and `redaction_confirmed.json` are **retained** as status markers — Cowork uses these to determine session state
- Session chunk files (`chunk_*.json`) are **retained** — already redacted, may be needed for Cowork re-analysis via standalone skills
- Generated documents (`clinical_notes.json`, `feedback.json`) are retained as the canonical file copy, indexed by the database

### Audio vs Transcript Retention
Audio and transcript have different lifecycles:
- **Raw audio** (`audio_chunks`) → deleted as soon as transcription completes and the session ends. Audio is never needed after the transcript exists.
- **Transcript segments** (in database) → retained for 2 weeks post-redaction. At `transcript_expires_at`, a forced-choice modal requires the clinician to either delete the transcript or generate notes first. This ensures the clinician has time to review and generate outputs, but doesn't retain raw transcript indefinitely.
- **Workspace chunks** (redacted `chunk_*.json` files) → retained with the session folder until client discharge. These are already redacted and safe. Cowork may need them for re-analysis.

### Forced-Choice Modal
When transcript_expires_at is reached, a modal appears that cannot be dismissed. The clinician must either delete the transcript or complete redaction and generate notes first. There is no auto-deletion without clinician action.

### Discharge Process
Discharging a client sets status to discharged and discharge_date. A clear notification informs the clinician that all client data will be permanently deleted in 30 days. Clinician can export anything needed before that date. At discharge + 30 days:
- All database records for the client are deleted (sessions, entities, mappings, feedback, documents)
- The workspace folder `Sessions/{initials}/` is deleted
- The private folder `Private/{initials}/` is deleted
- The practitioner_metrics records are NOT deleted (no client FK)

---

## 9. Application Flows

### Onboarding
1. Enter clinician name and title
2. Grant microphone access
3. Set Cowork working folder to `~/Library/Application Support/Redactor/Workspace/CoWork Files/`
4. Configure MCP server in Cowork settings (app provides instructions)
5. Brief instructions on workflow

### Client Workspace
From the client page the clinician has these entry points:

**Start recorded session** — Clinician goes to Cowork and types `/live-session`. Setup questions include client initials. Dashboard appears in Redactor automatically.
**View documents** — Browse and read all generated documents (notes, feedback, reports) with entity substitution (real names displayed).
**Feedback review** — Longitudinal view of feedback metrics across sessions. Signal labels applied at display time.
**Export** — Copy any document to clipboard with real names substituted, for pasting into CMS.

The following entry points require going to Cowork:
**Generate report** — `/report` skill in Cowork. App prepares `report_request.json` with source documents.
**Pre-session summary** — `/pre-session` skill in Cowork. Reads rolling summary and recent feedback.
**Caseload overview** — `/caseload` skill in Cowork. Cross-client analysis.

### Recorded Session Flow

**Phase 1 — Live session (Cowork: `/live-session`)**
Clinician opens Cowork → `/live-session` → answers setup questions (initials, type, goals, duration) → Cowork starts recording via MCP → live transcription and redaction in app → chunks exported to workspace with real-time (imperfect) redaction → Cowork polls and analyses → dashboard updates live → session ends → Cowork does final analysis summary → skill exits. Session status: `ended`.

**Phase 2 — Redaction review (App)**
Clinician opens app (when convenient — could be between sessions, lunch, end of day) → app shows sessions with status `ended` or `pending_redaction` → clinician opens redaction review → full transcript displayed with all detected entities → clinician confirms correct entities, corrects errors, merges duplicates, adds missed terms → confirmed new terms promoted to client's persistent redaction library → app rewrites all chunk files in workspace with corrected entity codes → app writes `redaction_confirmed.json` to session folder → session status: `redacted`.

**Phase 3 — Document generation (Cowork: `/process-sessions`)**
Clinician goes to Cowork → `/process-sessions` → Cowork scans all client folders for sessions with `redaction_confirmed.json` but no `clinical_notes.json` → for each session: reads corrected chunks, generates clinical notes (3 sections), generates feedback (7-pass), updates client rolling summary → app ingests all generated content → session status: `processed` → app presents notes and feedback with entity substitution → clinician reviews, edits, exports to CMS → transcript expires in 2 weeks → forced-choice modal.

### Work Session Flows

There are two types of non-recorded work:

**Rough notes (immediate transformation):**
Rough notes need immediate AI transformation — they go directly to Cowork. The clinician pastes or uploads rough notes into Cowork as part of a skill invocation (e.g., `/clinical-notes`). Cowork applies the redaction codes from the client's profile and generates structured output. The output is written via MCP tools and ingested by the app.

Flow: Clinician opens Cowork → `/clinical-notes JB` → pastes rough notes → Cowork generates structured clinical notes using client context → writes via `write_clinical_notes` → app ingests → display with entity substitution → export to CMS.

**Background documents (uploaded for reference):**
External reports, referral letters, prior assessments — these are uploaded to the app for long-term reference. They don't need immediate transformation but may be used as source material for report generation later.

Flow: Clinician uploads document in app → held in temp unredacted → redaction scan runs → therapist confirms terms → new terms merged into persistent redaction library → unredacted material deleted → redacted document stored in workspace at `Sessions/{initials}/external/` → indexed in database → available to Cowork via `get_document` MCP tool when generating reports.

### Post-Session Feedback Generation
Automated as the final phase of `/live-session` skill. Cowork runs 7 analysis passes over the full transcript:
- Pass 1: Listening quality
- Pass 2: Empathy, warmth, rupture repair, client engagement
- Pass 3: Partnership
- Pass 4: Goal alignment, session arc
- Pass 5: Persuasiveness, hope
- Pass 6: Cultivating change talk, softening sustain talk
- Pass 7 (synthesis): Derived scores (relational global, technical global, R:Q ratio, complex reflections %)

Cowork writes `feedback.json` to the session folder via MCP. The app ingests it: scores are parsed into individual columns in the `feedback_scores` table (for longitudinal queries), the narrative text is indexed in the `documents` table, and the JSON file remains in the workspace as the canonical document.

### Report Generation
Clinician selects report type (template or custom) in app. App writes `report_request.json` to `Sessions/{initials}/` with selected source document paths (session notes, external docs, rolling summary) and template instructions. Clinician goes to Cowork and types `/report JB`. Cowork reads `report_request.json`, fetches source documents via `get_document` MCP tool, generates report, writes to `Sessions/{initials}/reports/` via `write_report`. App ingests into documents table. Reports are client-level — they draw from multiple sessions and external documents.

### Pre-session Summary
Clinician goes to Cowork and types `/pre-session {initials}`. Cowork reads rolling summary, last session note, last feedback via MCP tools. Generates concise key-points brief. Displayed in Cowork (not stored — generated fresh each time).

---

## 10. UI Architecture

### Navigation
Two-level structure: client list (caseload view) → client workspace.

Caseload view shows all active clients with last session date and session count.

Client workspace shows client demographics, session history, document library, and feedback metrics.

### Session Type Defaults
Session type is set at client level and defaults to all new sessions for that client. Clinician can override per session in Cowork setup questions. Avoids repetitive data entry.

### Note Drafts
Notes are generated as drafts. The clinician can edit them freely within the app. There is no finalisation step — notes are always the most recent version. "Completed" means notes have been generated, not that they are locked. The app is not the source of truth for clinical records — the CMS is.

### Feedback Display
Signal labels applied at display time: 4-5 = Strength (green), 3 = On track (amber), 1-2 = Watch point (red), NULL = N/A. Not stored in database.

### Re-identification Display
All stored content contains substitution tokens. The app renders real names by applying entity_mappings in reverse at display time. The clinician always sees real names in the UI. This happens in memory — nothing re-identified is written.

### Document Viewer
A unified document viewer displays any generated document (notes, feedback narrative, reports) with:
- Entity substitution (real names)
- Section headers and formatting (markdown rendered)
- Copy to clipboard button (copies with real names)
- Section-level copy for partial export
- Edit capability for clinician amendments

### Dashboard
The live session dashboard displays real-time metrics during active sessions:
- Arc gauges for key metrics
- Coaching comment bar
- Therapist request buttons
- Entity-substituted display
- Status indicator for Cowork connection

---

## 11. Decisions Not Yet Made (Open Items)

1. **Feedback score domains in live session** — Which of the 11 constructs are calculated during live analysis vs post-session only. Post-session 7-pass builds on live session analysis — the two systems must be connected. To be resolved during SKILL.md development.
2. **7 redacted_persons variant codes** — Full list of derived variants to confirm from existing codebase during implementation.

---

## 12. What Is Explicitly Out of Scope for v1

- Multi-user or practice-level functionality
- CMS integration beyond copy/paste
- Cross-device sync
- Cloud backup
- Windows or cross-platform build
- Direct Anthropic API integration (future migration when privacy constraints are resolved)
- Video session recording
- Group session support
- Billing or invoicing
- Scheduling
- Interactive AI chat from within the app (requires direct API)

---

## 13. Document Index

| Document | Status | Notes |
|----------|--------|-------|
| Design Document v2.0 | This document | Cowork architecture |
| Database Schema v3 | Updated | Cowork-aligned, chat tables removed |
| File Structure Map v2 | Updated | Workspace + app storage model |
| Cowork Integration Spec v1 | Updated | Replaces API Integration Spec |
| Transcript Notes Transformation | Complete | Prompt spec for clinical note generation |
| Implementation Plan | Complete | 14-phase build plan with service import manifest |
| SKILL.md Specifications | Pending | Detailed workflow specs for each skill |
