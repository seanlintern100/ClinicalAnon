# Redactor — Cowork Integration Specification
## Version 1.0

---

## Overview

Redactor uses Claude Cowork as its AI generation layer. The app and Cowork communicate through three interfaces:

1. **MCP Server** — Python process providing MCP tools that Cowork calls
2. **HTTP Server** — Swift server inside the app that executes MCP tool requests
3. **SKILL.md Files** — Workflow definitions Cowork discovers as slash commands

The app is the system of record. Cowork is the generation engine. All generated content passes through the app's validation and storage layer.

### Future API Migration
The data layer (database schema, file structure, document format) and UI are designed to work regardless of how AI content arrives — they are transport-agnostic. When migrating to direct API:
- MCP tools → Swift-executed tool definitions in API requests
- HTTP server → unnecessary (app calls API directly)
- SKILL.md workflows → system prompts with tool definitions. **This is a significant rewrite** — skills contain Cowork-specific workflow logic (polling loops, session state management, interaction patterns) that don't translate 1:1 to API tool-use calls
- Data flow remains identical: AI generates → app validates → app stores → app displays
- No changes to database schema, file structure, UI, or document format
- The app would gain the ability to trigger AI work directly, removing the "clinician must initiate in Cowork" constraint

---

## MCP Server

### Configuration
The MCP server (`redactor_mcp_server.py`) is configured in Cowork's settings:

```json
{
  "mcpServers": {
    "redactor": {
      "command": "<workspace>/.venv/bin/python3",
      "args": ["<path-to>/redactor_mcp_server.py"],
      "env": {
        "REDACTOR_EXPORT_ROOT": "~/Library/Application Support/Redactor/Workspace/Sessions"
      }
    }
  }
}
```

The MCP server is a thin proxy — it forwards all requests to the app's HTTP server on port 8787. Tool implementations live in the app (Swift), not the MCP server (Python).

### Token Authentication
The app generates a persistent token on first launch and stores it at `Workspace/.server_token`. The MCP server reads this token from `REDACTOR_EXPORT_ROOT/../.server_token` (the workspace root) and includes it in all HTTP requests to the app's server. The token is app-wide and persists across sessions.

For non-session tools (list_clients, get_client_profile), the MCP server connects to the HTTP server's standby endpoints which do not require a session to be active.

---

## HTTP Server

### Lifecycle
- Starts in standby mode on app launch (only `/health` responds)
- `/start` endpoint activates a session (creates token, writes `.server_token`)
- All session endpoints require token (query string `?token=X` or `Authorization` header)
- Standby endpoints (`/health`, `/clients`, `/client-profile`) work without a session token
- Runs on port 8787

### Body Parsing
POST body parsing accumulates TCP packets using Content-Length header for reliable large payloads.

---

## MCP Tool Definitions

### Recording Control

#### start_recording
Start audio recording and transcription for a session.
- **Parameters:** `initials` (string, required), `session_type` (string), `session_goals` (string), `duration_minutes` (integer)
- **Returns:** `{ session_id, session_folder }`
- **Side effects:** Creates session folder, writes session_info.json, activates session token, begins audio capture and transcription

#### stop_recording
Stop recording. Triggers session_complete marker.
- **Parameters:** none (uses active session)
- **Returns:** `{ status: "stopped", chunks_exported: N }`
- **Side effects:** Writes session_complete.json, stops audio capture

#### pause_recording / resume_recording
Pause or resume recording during session.
- **Parameters:** none
- **Returns:** `{ status: "paused" | "recording" }`

---

### Session Data (Live)

#### get_new_chunks
Get redacted transcript chunks since a given index.
- **Parameters:** `since_index` (integer, required)
- **Returns:** `{ chunks: [...], latest_index: N }`
- **Scoping:** Returns only chunks from the active session folder

#### get_session_info
Get session metadata.
- **Parameters:** none
- **Returns:** `{ session_id, initials, session_type, session_date, session_goals, duration_minutes, elapsed_seconds }`

#### get_session_state
Get current analysis state for the dashboard.
- **Parameters:** none
- **Returns:** JSON object with all dashboard metrics, themes, people, risk, coaching_comment, therapist_request

#### write_session_state
Push updated analysis state to the dashboard.
- **Parameters:** `state` (JSON object, required) — full session state
- **Returns:** `{ status: "ok" }`
- **Validation:** App validates JSON structure before writing
- **Schema:**
```json
{
  "client_talk_pct": 62,
  "engagement_score": 4.2,
  "rq_ratio": 1.4,
  "ex_pct": 8,
  "utterance_counts": { "Q": 12, "SR": 8, "CR": 5, "EX": 3, "O": 2 },
  "rolling_10min": { "client_talk_pct": 65, "rq_ratio": 1.6 },
  "agenda_items": [
    { "item": "Workplace anxiety triggers", "status": "partially_discussed", "evidence": "..." }
  ],
  "themes": [
    { "theme": "workplace powerlessness", "count": 4 }
  ],
  "people_and_details": [
    { "code": "[PERSON_B]", "role": "manager at [ORG_A]", "context": "source of conflict" }
  ],
  "rupture_indicators": [],
  "risk_flags": [],
  "coaching_comment": "Strong use of open questions in exploring workplace dynamics.",
  "therapist_request": null,
  "therapist_request_response": null
}
```
- **Note:** This is transient — never ingested into the database. Dashboard reads it directly from the file. Discarded after session cleanup.

#### is_session_complete
Check if recording has ended.
- **Parameters:** none
- **Returns:** `{ complete: true|false, total_chunks: N }`

---

### Session Processing

#### get_unprocessed_sessions
List all sessions that have been redaction-confirmed but not yet processed (notes/feedback not generated). Used by `/process-sessions` skill to find work.
- **Parameters:** none (scans all client folders)
- **Returns:**
```json
{
  "sessions": [
    {
      "initials": "JB",
      "session_id": "JB_2026-03-20_0937",
      "session_folder": "JB/2026-03-20_0937",
      "session_type": "therapy",
      "session_date": "2026-03-20",
      "chunk_count": 15,
      "has_notes": false,
      "has_feedback": false
    }
  ]
}
```
- **Logic:** A session is "unprocessed" if its folder contains `redaction_confirmed.json` but not `clinical_notes.json`. Sessions with `session_complete.json` but no `redaction_confirmed.json` are skipped (awaiting therapist review in the app).

---

### Content Generation

#### write_clinical_notes
Write clinical notes to the session folder.
- **Parameters:** `notes` (JSON object, required)
- **Schema:**
```json
{
  "session_id": "JB_2026-03-20_0937",
  "generated_at": "2026-03-20T10:35:00Z",
  "sections": {
    "clinical_notes": "...",
    "client_summary": "...",
    "clinical_review": "..."
  }
}
```
- **Returns:** `{ status: "ok", path: "clinical_notes.json" }`
- **Side effects:** App detects file, ingests into document index, notifies UI

#### write_feedback
Write feedback scores and narrative to the session folder.
- **Parameters:** `feedback` (JSON object, required)
- **Schema:**
```json
{
  "session_id": "JB_2026-03-20_0937",
  "generated_at": "2026-03-20T10:35:00Z",
  "scores": {
    "listening_quality": 4,
    "empathy": 5,
    "warmth": 4,
    "rupture_repair": null,
    "client_engagement": 4,
    "partnership": 3,
    "goal_alignment": 4,
    "session_arc": 5,
    "persuasiveness": 3,
    "hope": 4,
    "cultivating_change_talk": null,
    "softening_sustain_talk": null,
    "relational_global": 4.2,
    "technical_global": 3.8,
    "reflection_question_ratio": 1.4,
    "complex_reflections_pct": 0.35
  },
  "narrative": "Full feedback narrative text...",
  "pass_details": {
    "pass_1_listening": "...",
    "pass_2_relational": "...",
    "pass_3_partnership": "...",
    "pass_4_structure": "...",
    "pass_5_influence": "...",
    "pass_6_mi_specific": "...",
    "pass_7_synthesis": "..."
  }
}
```
- **Returns:** `{ status: "ok", path: "feedback.json" }`
- **Side effects:** App ingests scores into feedback_scores table, narrative into documents

#### write_rolling_summary
Update the client's rolling clinical summary.
- **Parameters:** `initials` (string, required), `summary` (string, required)
- **Returns:** `{ status: "ok" }`
- **Side effects:** Writes/overwrites `Sessions/{initials}/rolling_summary.md`

#### write_report
Write a generated report to the client's reports folder (client-level, not session-level).
- **Parameters:** `initials` (string, required), `report` (JSON object, required)
- **Schema:**
```json
{
  "report_type": "formal_report",
  "template_name": "ACC Initial Assessment",
  "generated_at": "2026-03-20T10:35:00Z",
  "content": "Full report content in markdown..."
}
```
- **Returns:** `{ status: "ok", path: "reports/formal_report_2026-03-20.json" }`
- **Side effects:** Written to `Sessions/{initials}/reports/`. App ingests into documents table with `document_type = 'formal_report'`.

### Report Request

The app writes `report_request.json` to a client's workspace folder when the clinician initiates a report from the app UI. Cowork reads this file when the `/report` skill is invoked.

**report_request.json schema:**
```json
{
  "initials": "JB",
  "report_type": "formal_report",
  "template_name": "ACC Initial Assessment",
  "template_instructions": "Full template instruction text...",
  "source_documents": [
    { "path": "2026-03-20_0937/clinical_notes.json", "type": "session_note" },
    { "path": "2026-03-15_1400/clinical_notes.json", "type": "session_note" },
    { "path": "rolling_summary.md", "type": "rolling_session_summary" }
  ],
  "additional_instructions": "Optional clinician notes for report generation",
  "created_at": "2026-03-20T11:00:00Z"
}
```

Written by the app when clinician selects report type and source documents. Deleted after Cowork completes report generation.

---

### Client Context

#### get_client_profile
Read client profile metadata for AI context.
- **Parameters:** `initials` (string, required)
- **Returns:** Contents of `Sessions/{initials}/client_profile.json`:
```json
{
  "initials": "JB",
  "preferred_name": "[CLIENT_A_FIRST]",
  "pronouns": "he/him",
  "default_session_type": "therapy",
  "default_session_type_desc": null,
  "default_duration_minutes": 50,
  "session_count": 12,
  "last_session_date": "2026-03-15",
  "onboarding_date": "2025-06-01",
  "status": "active"
}
```
- **Note:** No real names. `preferred_name` uses the redaction code. The app writes this file from database data with entity substitution applied. Schema matches the file structure document exactly.

#### list_clients
List all client folders with basic metadata.
- **Parameters:** none
- **Returns:**
```json
{
  "clients": [
    {
      "initials": "JB",
      "session_count": 12,
      "last_session_date": "2026-03-15",
      "has_rolling_summary": true
    }
  ]
}
```
- **Scoping:** No session token required. Returns all client folders.

#### list_sessions
List all sessions for a client.
- **Parameters:** `initials` (string, required)
- **Returns:**
```json
{
  "sessions": [
    {
      "session_id": "JB_2026-03-20_0937",
      "date": "2026-03-20",
      "session_type": "therapy",
      "has_notes": true,
      "has_feedback": true,
      "chunk_count": 15
    }
  ]
}
```

#### get_document
Read a specific document from a client's workspace folder.
- **Parameters:** `initials` (string, required), `path` (string, required) — relative path within the client's folder
- **Returns:** File content as string
- **Scoping:** HTTP server validates the path is within `Sessions/{initials}/` — no path traversal

#### health_check
Verify connection to the app.
- **Parameters:** none
- **Returns:** `{ status: "ok", version: "2.0", session_active: true|false }`

---

## SKILL.md Generation

The app generates all SKILL.md files on launch via `SessionExportService`. Skills are written to `Workspace/CoWork Files/.claude/skills/`. Cowork discovers them as slash commands when the user opens `CoWork Files/` as their working folder.

### Skill Structure
Each SKILL.md follows this structure:
```markdown
---
name: skill-name
description: One-line description
---

## Purpose
What this skill does

## Setup
Questions to ask the user before starting

## Workflow
Step-by-step MCP tool sequence

## Rules
Analysis rules, output format, constraints

## Output
What to generate and how to write it via MCP tools
```

### CLAUDE.md — Critical for Cowork Discovery
The app writes `CLAUDE.md` to `CoWork Files/` root. **This file is essential** — Cowork relies on CLAUDE.md to discover available tools, folder structure, and workflow context. Without explicit registration in CLAUDE.md, Cowork may miss MCP tools, skills, or workspace paths.

CLAUDE.md must include:
- **All MCP tool names and descriptions** — Cowork needs to know what tools are available and what each one does. If a tool is not listed here, Cowork may not use it even if it's defined in the MCP server.
- **Workspace folder structure** — Explicit description of `Sessions/{initials}/` layout, what files exist where, and what Cowork can read vs write.
- **Available skills** — List of slash commands with one-line descriptions so Cowork can suggest them to the user.
- **Privacy rules** — Entity code formatting (always use `[BRACKETS]`), never attempt to infer real names, never include identifying information in outputs.
- **Clinician context** — Clinician name and title (used in generated outputs).
- **Output format rules** — JSON schemas for each content type Cowork writes via MCP tools.

The app regenerates CLAUDE.md on every launch. To modify what Cowork sees, edit the generation code in `SessionExportService`, not the file directly.

**Example CLAUDE.md structure:**
```markdown
# Redactor Clinical Assistant

You are a clinical assistant working alongside a registered psychologist.
All client data is de-identified. Use only substitution tokens like [CLIENT_A], [PERSON_B].

## Clinician
Name: {clinician_name}
Title: {clinician_title}

## Available Skills
- /live-session — Record and analyse a therapy session in real time (exits when session ends)
- /process-sessions — Generate notes and feedback for all sessions awaiting processing
- /clinical-notes — Generate clinical notes for a specific session
- /feedback — Generate practitioner feedback for a specific session
- /report — Generate a formal report from selected documents
- /pre-session — Generate a pre-session brief for a returning client
- /caseload — Cross-client caseload overview and metrics

## MCP Tools Available
- health_check — Check connection to the Redactor app
- start_recording(initials, session_type, session_goals, duration_minutes) — Start recording
- stop_recording — Stop recording
- pause_recording / resume_recording — Pause or resume
- get_new_chunks(since_index) — Get redacted transcript chunks
- get_session_info — Session metadata
- get_session_state — Current dashboard analysis state
- write_session_state(state_json) — Push analysis to dashboard
- is_session_complete — Check if recording has ended
- get_unprocessed_sessions — List sessions ready for processing (redaction confirmed, not yet processed)
- write_clinical_notes(notes_json) — Save clinical notes
- write_feedback(feedback_json) — Save feedback scores and narrative
- write_rolling_summary(initials, summary_text) — Update rolling clinical summary
- write_report(initials, report_json) — Save a generated report
- get_client_profile(initials) — Read client profile
- list_clients — List all clients
- list_sessions(initials) — List sessions for a client
- get_document(initials, path) — Read a document

## Workspace Structure
Sessions/
  index.json — Root index of all clients (read this first for caseload tasks)
  {INITIALS}/ — One folder per client
    client_profile.json — Client metadata (read via get_client_profile)
    client_index.json — Index of all sessions and documents for this client
    rolling_summary.md — Running clinical summary
    reports/ — Generated reports (client-level, not session-level)
    external/ — Uploaded background documents (redacted)
    report_request.json — Report generation request (when applicable)
    {YYYY-MM-DD_HHMM}/ — Session folders
      session_info.json, chunk_*.json, clinical_notes.json, feedback.json
      session_complete.json, redaction_confirmed.json — status markers

## Important: Always read index files first
- For caseload tasks: read Sessions/index.json before accessing client folders
- For client tasks: read Sessions/{INITIALS}/client_index.json before accessing session folders
- These files are your navigation map — they tell you what exists and where

## Entity Code Rules
- Always use square brackets: [PERSON_A], [CLIENT_A_FIRST], [ORG_A]
- Never use bare codes without brackets
- Use _FIRST suffix for natural reading throughout generated text
- Use [THERAPIST] where therapist attribution is needed
```

---

## Content Ingestion

When Cowork writes generated content via MCP tools, the app ingests it:

1. **Detection:** HTTP server receives the write request, or file watcher detects new file
2. **Validation:** Check JSON schema, verify content is in redacted form (contains substitution tokens, no real names)
3. **Database update:** Create/update records in documents table, feedback_scores table as appropriate
4. **UI notification:** Post notification so active views refresh
5. **Display:** Document viewer shows content with entity substitution (real names)

### Ingestion by content type

| Content | Written by Cowork | Ingested into |
|---------|------------------|---------------|
| clinical_notes.json | write_clinical_notes | documents table (session_note, client_note) |
| feedback.json | write_feedback | feedback_scores table + documents table (feedback_narrative) |
| rolling_summary.md | write_rolling_summary | documents table (rolling_session_summary) |
| report output | write_report | documents table (formal_report) |
| session_state.json | write_session_state | Not ingested — transient, dashboard only |

---

## Error Handling

**MCP server errors:** If the app's HTTP server is unreachable, the MCP server returns a structured error to Cowork. Cowork retries on the next polling cycle.

**Live session failures:** If a polling cycle fails, the dashboard holds its last known state and shows a status indicator. Recording and transcription continue unaffected. Recovery is attempted on the next cycle.

**Invalid content:** If Cowork attempts to write content that fails validation (missing required fields, appears to contain unredacted names), the HTTP server rejects the write and returns an error message instructing Cowork to correct the output.

**Session token expiry:** Tokens are valid for the duration of a session. If a token becomes invalid (session ended, app restarted), the MCP server discovers the current token from the most recent `.server_token` file.

---

## Cowork Setup Instructions

The app provides a first-time setup flow that guides the clinician through:

1. Install Claude Cowork (if not installed)
2. Open Cowork settings → MCP Servers → Add server with the provided configuration
3. Set working folder to `~/Library/Application Support/Redactor/Workspace/CoWork Files/`
4. Verify connection: type `/live-session` and confirm the skill is discovered
5. Run health_check to confirm MCP → HTTP → app connection

The app can verify the connection is working via the HTTP server's health endpoint.
