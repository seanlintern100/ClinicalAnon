# Redactor — AI Integration Specification
## Version 2.0 — Claude Code Architecture

---

## Overview

Redactor uses Claude Code (Anthropic's CLI agent tool) as its AI generation layer. The app spawns `claude -p` as a subprocess to trigger AI workflows. Claude Code connects to the app's MCP server for data access and content writing.

**Three interfaces:**

1. **MCP Server** (`redactor_mcp_server.py`) — Python FastMCP process providing tools. Claude Code connects via stdio. The server proxies requests over HTTP to the app's internal server.
2. **HTTP Server** (`CopilotHTTPServer.swift`, port 8787) — Swift TCP server inside the app that executes MCP tool requests. Runs in standby on launch.
3. **System Prompts** — Workflow instructions embedded in the app (one per AI task). Passed to Claude Code via `--append-system-prompt`. Replace the previous SKILL.md file-based approach.

The app is the system of record. Claude Code is the generation engine. All generated content passes through the app's validation and storage layer.

### How the App Triggers Claude Code

```swift
// Example: Generate clinical notes for a session
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
process.arguments = [
    "-p", prompt,
    "--append-system-prompt", systemPrompt,
    "--allowedTools", "mcp__redactor__get_new_chunks,mcp__redactor__write_clinical_notes,...",
    "--output-format", "json",
    "--json-schema", notesSchema,
    "--mcp-config", mcpConfigPath
]
```

**Key flags:**
- `-p` — non-interactive mode (run prompt, return result, exit)
- `--append-system-prompt` — workflow instructions (replaces SKILL.md)
- `--allowedTools` — restrict to MCP tools only (security)
- `--output-format json` — structured response with metadata
- `--json-schema` — enforce response shape (e.g., feedback scores)
- `--resume SESSION_ID` — multi-turn conversations (live analysis loop)
- `--output-format stream-json` — real-time streaming for live dashboard

### Future Direct API Migration
The data layer, document storage, and UI are AI-transport-agnostic. Migration to direct Anthropic API requires:
- System prompts → API system prompts (identical content)
- MCP tools → tool definitions in API requests (same schemas)
- HTTP server + MCP server → unnecessary (app calls API directly)
- `claude -p` subprocess → `URLSession` API call
- No changes to database schema, file structure, UI, or document format

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

## System Prompts (replaces SKILL.md)

The app embeds system prompts for each AI workflow. These are passed to Claude Code via `--append-system-prompt` when spawning the subprocess. The system prompt content is identical to what was previously in SKILL.md files — workflow instructions, analysis rules, output format constraints.

### System Prompt Structure
Each workflow has a system prompt containing:
- **Purpose** — what this workflow does
- **MCP tools available** — which tools to use and in what order
- **Workflow steps** — step-by-step process
- **Analysis rules** — domain-specific rules (utterance classification, feedback scoring, etc.)
- **Output format** — JSON schema for the response
- **Privacy rules** — entity code brackets, never infer real names

### ClaudeCodeService — Manages AI Workflows
The app's `ClaudeCodeService` manages all Claude Code interactions:

```swift
class ClaudeCodeService {
    // Check if claude CLI is available
    func isAvailable() -> Bool

    // Spawn claude -p for a one-shot workflow
    func runWorkflow(
        prompt: String,
        systemPrompt: String,
        allowedTools: [String],
        jsonSchema: String?,
        workingDirectory: URL
    ) async throws -> WorkflowResult

    // Spawn claude -p with streaming for live analysis
    func runStreamingWorkflow(
        prompt: String,
        systemPrompt: String,
        allowedTools: [String],
        sessionId: String?,
        onEvent: (StreamEvent) -> Void
    ) async throws

    // Resume a multi-turn conversation
    func resumeSession(
        sessionId: String,
        prompt: String
    ) async throws -> WorkflowResult
}
```

### Available Workflows

| Workflow | Trigger | Mode | System Prompt |
|----------|---------|------|---------------|
| Live Session Analysis | Recording starts | Streaming + multi-turn | `liveSessionPrompt` |
| Process Sessions | Clinician clicks "Process" | One-shot | `processSessionsPrompt` |
| Clinical Notes | Clinician clicks "Generate Notes" | One-shot | `clinicalNotesPrompt` |
| Feedback | Clinician clicks "Generate Feedback" | One-shot | `feedbackPrompt` |
| Report | Clinician clicks "Generate Report" | One-shot | `reportPrompt` |
| Pre-Session Brief | Clinician clicks "Pre-Session" | One-shot | `preSessionPrompt` |
| Caseload Overview | Clinician clicks "Caseload" | One-shot | `caseloadPrompt` |

### MCP Configuration for Claude Code

The app writes an MCP config file that Claude Code reads:

```json
{
  "mcpServers": {
    "redactor": {
      "command": "python3",
      "args": ["/path/to/redactor_mcp_server.py"],
      "env": {
        "REDACTOR_EXPORT_ROOT": "~/Library/Application Support/Redactor/Workspace/Sessions"
      }
    }
  }
}
```

This is passed to Claude Code via `--mcp-config /path/to/mcp_config.json`.

### Context Passed to Claude Code

Each workflow invocation includes:
- **System prompt** with workflow instructions, analysis rules, and MCP tool guidance
- **User prompt** with the specific task (e.g., "Process session JB/2026-03-20_0937")
- **MCP tools** restricted via `--allowedTools` to only the tools needed for that workflow
- **JSON schema** (where applicable) via `--json-schema` for structured output

The system prompt includes the same content that was in the CLAUDE.md + SKILL.md files:
- Clinician name/title
- MCP tool descriptions
- Workspace structure
- Privacy rules (entity code brackets)
- Analysis rules (utterance classification, feedback scoring, etc.)

---

## Content Ingestion

When Claude Code writes generated content via MCP tools, the app ingests it:

1. **Detection:** HTTP server receives the write request from the MCP tool
2. **Validation:** Check JSON schema, verify content is in redacted form (contains substitution tokens, no real names)
3. **Database update:** Create/update records in documents table, feedback_scores table as appropriate
4. **UI notification:** Post notification so active views refresh
5. **Display:** Document viewer shows content with entity substitution (real names)

### Ingestion by content type

| Content | Written via MCP tool | Ingested into |
|---------|---------------------|---------------|
| clinical_notes.json | write_clinical_notes | documents table (session_note, client_note) |
| feedback.json | write_feedback | feedback_scores table + documents table (feedback_narrative) |
| rolling_summary.md | write_rolling_summary | documents table (rolling_session_summary) |
| report output | write_report | documents table (formal_report) |
| session_state.json | write_session_state | Not ingested — transient, dashboard only |

---

## Error Handling

**MCP server errors:** If the app's HTTP server is unreachable, the MCP server returns a structured error to Claude Code. Claude Code includes the error in its response to the app.

**Claude Code process errors:** If the subprocess crashes or times out, the app shows an error to the clinician and allows retry. Recording and transcription continue unaffected — AI analysis is decoupled from audio capture.

**Invalid content:** If Claude Code attempts to write content that fails validation (missing required fields, appears to contain unredacted names), the HTTP server rejects the write and returns an error message.

**Session token management:** The app generates a persistent token stored in `Workspace/.server_token`. The MCP server reads this token fresh on every tool call. The token persists across sessions and app restarts.

---

## Claude Code Setup Instructions

The app provides a first-time setup flow:

1. **Check for Claude Code:** App checks if `claude` is in PATH on launch
2. **If not installed:** Show setup guide with install command: `brew install --cask claude-code`
3. **Authentication:** Clinician runs `claude` once in terminal to authenticate via browser (one-time)
4. **Verification:** App spawns `claude -p "hello" --output-format json` to verify the CLI works
5. **MCP config:** App writes MCP config file and verifies connection via `health_check` tool

No manual MCP server configuration needed — the app handles it programmatically via `--mcp-config`.
