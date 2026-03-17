# Cowork Live Session Pipeline — Instructions

## Overview

Redactor Lite exports redacted transcript chunks to a watched folder during live recording sessions. Your job is to collect session setup info from the therapist, launch the app, process each chunk, run local calculations and AI analysis, maintain session state, and render the live dashboard.

**Privacy rule:** The `entity_map.json` file maps redaction codes to real names. Use it ONLY for dashboard display. Never include real names in AI API calls — all AI receives redacted text only.

---

## Session Setup (Before Recording)

When the therapist asks to start a session, collect session info using the `AskUserQuestion` tool. Use **two** question blocks to keep it quick.

### Question block 1 — Session basics

Ask all four questions in a single `AskUserQuestion` call:

```
Question 1: "What are the client's initials?"
  header: "Client ID"
  options: (use "Other" — the user always types initials as free text)
  multiSelect: false

Question 2: "What type of session is this?"
  header: "Type"
  options:
    - label: "Therapy"        description: "Standard therapeutic session"
    - label: "Coaching"       description: "Coaching or mentoring session"
    - label: "Supervision"    description: "Clinical supervision session"
    - label: "Other"          description: "Specify session type"
  multiSelect: false

Question 3: "How long is the session?"
  header: "Length"
  options:
    - label: "50 min"         description: "Standard session (Recommended)"
    - label: "30 min"         description: "Brief check-in"
    - label: "80 min"         description: "Extended session"
    - label: "90 min"         description: "Long session"
  multiSelect: false

Question 4: "Is anyone else joining the client today?"
  header: "Speakers"
  options:
    - label: "1:1 session"    description: "Just the client on the remote end (Recommended)"
    - label: "Multiple"       description: "Couples, family, or group — enables speaker identification"
  multiSelect: false
```

### Question block 2 — Session goals

After block 1, ask goals as free text:

```
Question 1: "What are your goals for this session?"
  header: "Goals"
  options:
    - label: "General check-in"   description: "No specific focus area"
    - label: "Continue previous"   description: "Continue from where last session left off"
  multiSelect: false
  (The therapist will typically choose "Other" and type specific goals)
```

### Defaults

- **Session date**: today (no need to ask)
- **Session length**: 50 minutes is the default/recommended option
- **Multiple speakers**: 1:1 is the default/recommended option

### Mapping answers to URL parameters

| Answer | URL parameter |
|---|---|
| Client initials (free text) | `initials=JB` |
| Session type label | `type=Therapy` |
| Length — extract number from label | `length=50` |
| Goals (free text or label) | `goals=Explore+anxiety+triggers` |
| Speakers — "1:1 session" → false, "Multiple" → true | `multiSpeaker=false` |

### Launching the app

Once you have all the info, write a trigger file to the Cowork export folder. The Redactor app watches this folder and will auto-start recording when it finds the trigger.

**Important:** The Redactor app must already be open (it starts the file watcher on launch). If it's not running, tell the therapist to open it first.

**Step 1 — Find the export folder.** This is the same folder you monitor for chunk files. It is the workspace folder that has been selected/mounted for this session.

**Step 2 — Write the trigger file.** Create `.cowork_trigger.json` in the export root folder (NOT inside a session subfolder):

```bash
cat > /path/to/export/folder/.cowork_trigger.json << 'EOF'
{
  "initials": "JB",
  "type": "Therapy",
  "length": 50,
  "goals": "Explore anxiety triggers",
  "multiSpeaker": false
}
EOF
```

**Field reference:**

| Field | Type | Required | Values |
|---|---|---|---|
| `initials` | string | yes | Client initials, e.g. "JB" |
| `type` | string | no | "Therapy", "Coaching", "Supervision", "Other" (default: Therapy) |
| `otherType` | string | no | Description if type is "Other" |
| `length` | int | no | Minutes, 10–180 (default: 50) |
| `goals` | string | no | Session goals free text |
| `multiSpeaker` | bool | no | true for couples/family/group (default: false) |

**What happens:** The app detects the trigger file within 2 seconds, reads the metadata, deletes the trigger file, opens the recording window with pre-filled settings, starts recording, starts an HTTP server on `127.0.0.1:8787`, and opens the live dashboard in the default browser — all automatically. The therapist doesn't need to touch the app.

### After launch

The app handles:
- Recording and transcription
- Exporting redacted chunks to the session folder
- Serving the live dashboard via HTTP (`http://127.0.0.1:8787/dashboard`)
- Opening the dashboard in the browser automatically

Cowork handles:
- Processing chunks (local calculations + AI analysis)
- Writing `session_state.json` to the session folder (which the app's HTTP server serves to the dashboard)

Once the app is recording, chunk files will appear in the session folder. Proceed to **Folder Watching** below to start processing.

---

## Folder Watching

You must continuously monitor the session folder for new chunk files throughout the recording session.

### How to poll

List the session folder every **5 seconds** and compare against the chunks you have already processed. When a new `chunk_NNN.json` file appears, process it immediately through the pipeline (Steps 1–5 below).

### Detecting a new session

Watch the root export folder for new subdirectories. When a new folder appears containing `session_info.json`, that is a new session starting. Read `session_info.json` and `entity_map.json`, initialise session state, and begin polling for chunk files.

### When to stop

Stop polling when `session_complete.json` appears in the session folder. This file is written by the app when the therapist stops the recording:

```json
{
  "session_id": "JB_2026-03-17_1430",
  "chunks_exported": 12,
  "completed_at": "2026-03-17T15:22:04+13:00"
}
```

After `session_complete.json` appears:
1. Process any remaining unprocessed chunks
2. Re-read `entity_map.json` one final time (it may have been updated with the last chunk)
3. Run a final dashboard render
4. The session is complete — no further polling needed

### Polling summary

```
1. Watch root folder for new session subfolder
2. On new session: read session_info.json, init state, begin polling
3. Every 5 seconds: list folder, process any new chunk_NNN.json files
4. On session_complete.json: process remaining chunks, stop polling
```

---

## Folder Structure

When a session starts, a folder appears like:

```
{watched_root}/
  JB_2026-03-17_1430/
    session_info.json       ← written once at session start
    entity_map.json         ← updated after each chunk (code → real name)
    chunk_001.json          ← first transcript chunk
    chunk_002.json          ← arrives ~60s later
    ...
    session_complete.json   ← written when recording stops (signals end of session)
```

### session_info.json

```json
{
  "session_id": "JB_2026-03-17_1430",
  "session_type": "therapy",
  "session_date": "2026-03-17",
  "session_duration_minutes": 50,
  "therapist_goals": [
    "Explore sleep disruption patterns",
    "Boundary-setting with mother",
    "Review coping strategies from last session"
  ],
  "entity_map_version": "1"
}
```

### entity_map.json

```json
{
  "version": "1",
  "mappings": {
    "PERSON_A": "Jamie Smith",
    "PERSON_A_FIRST": "Jamie",
    "PERSON_A_LAST": "Smith",
    "LOCATION_A": "Wellington",
    "DATE_A": "15 March 2026"
  }
}
```

**Usage:** At render time, substitute `[PERSON_A]` → the real name from this map. The therapist sees real names on screen. AI never sees them.

### chunk_NNN.json

```json
{
  "chunk_index": 1,
  "session_id": "JB_2026-03-17_1430",
  "timestamp_start": "00:00:00",
  "timestamp_end": "00:01:02",
  "segments": [
    {
      "speaker": "therapist",
      "text": "So when [PERSON_A] said that, what came up for you?",
      "timestamp": "00:00:04"
    },
    {
      "speaker": "client",
      "text": "I just felt like I'd failed again. Like I always do.",
      "timestamp": "00:00:11"
    }
  ]
}
```

Chunks are ~60 seconds, soft-bounded at utterance end (58–65s). Process in `chunk_index` order — hold out-of-order chunks.

Speaker labels: `therapist` (microphone), `client` (single remote speaker), `client_1`/`client_2` (if diarization detects multiple remote speakers).

---

## Processing Pipeline

For each new chunk file:

### Step 1 — Parse & sequence check

Read chunk JSON. Confirm `chunk_index` is the next expected. If a gap, hold until preceding chunk arrives.

### Step 2 — Local calculations (no AI)

Update these from segment data directly:

**Speaker totals:**
```
segment_duration = word_count × 0.4 seconds (estimate)
client_seconds += sum of client segment durations
therapist_seconds += sum of therapist segment durations
client_talk_pct = client_seconds / (client_seconds + therapist_seconds) × 100
```

**Rolling 10-minute window:**
Keep a buffer of all segments. For the 10m window, sum only segments whose timestamp falls within [now - 600s, now]. Calculate the same talk%, R:Q, and engagement for this window.

**Client engagement (composite, no AI):**
```
talk_time_component = client_talk_pct (0–100)
turn_length_component = min(mean_client_words_per_turn / 40 × 100, 100)
elaboration_component = (elaborated_turns / total_client_turns) × 100
  elaborated turn = client segment with ≥ 3 sentences OR ≥ 40 words

engagement_score = (talk_time_component × 0.5)
                 + (turn_length_component × 0.3)
                 + (elaboration_component × 0.2)
```

### Step 3 — AI analysis

Send the chunk with **only the context each analysis needs** — NOT the full session state. The pipeline owns all counts and accumulation. The AI classifies and synthesises, but never re-counts.

**Input to AI (assembled by pipeline):**
1. The new chunk JSON (redacted — safe to send)
2. Therapist goals from session_info.json
3. Current agenda items (status + evidence summaries) — so AI can update status and refine evidence
4. Existing people list — so AI can merge, not duplicate
5. Existing themes with phrases — so AI can assign phrases or create new themes
6. Recent client segments (last 2–3 chunks) — for rupture detection comparison only

**Do NOT send:** Full session state, raw utterance counts, speaker totals, engagement scores, or prior chunk text beyond the rupture lookback window. The pipeline calculates these locally.

**Output from AI:** A delta JSON object (see `ai-prompt-template.md` for exact format and rules).

**What the pipeline calculates locally (no AI):**
- Speaker totals, client talk %, rolling 10m window
- R:Q ratio (accumulated from AI's per-chunk classifications)
- Client engagement score (word counts, turn lengths, elaboration)
- Risk flag (rule-based keyword matching on client segments)

### Step 4 — Merge AI delta into session state

Apply each field from the delta:

- **utterance_classifications** → increment `therapist_questions`, `therapist_sr`, `therapist_cr` counts. Recalculate `rq_ratio = (sr + cr) / questions`.
- **agenda_updates** → update status (one-directional: not_discussed → partially → fully). Apply evidence actions: `append` adds, `synthesise` replaces with refined text, `prune` removes.
- **new_client_agenda_items** → add to client agenda (only if confidence is "high" and appears across ≥ 2 client turns).
- **people_updates** → update or add to people list. Merge new details and events.
- **theme_updates** → apply actions: `add_phrase`, `new_theme`, `rename`, `merge`. Maintain 3–7 themes. If `new_theme` includes `replaces`, remove the replaced theme and reassign its phrases.
- **rupture_signal** → if non-null, set rupture detected. Include type ("withdrawal" or "confrontation"), chunk_index, and timestamp.
- **risk_signal** → if non-null, set risk flagged. Persistent once raised — never cleared during session.

### Step 5 — Update dashboard

Write the updated session state to a shared local file (e.g., `session_state.json` in the session folder). The dashboard watches this file and re-renders on change.

---

## Session State Schema

The complete session state object (in-memory, updated each chunk):

```json
{
  "session_id": "JB_2026-03-17_1430",
  "session_type": "therapy",
  "session_start": "14:30:00",
  "session_duration_seconds": 3000,
  "chunks_processed": 0,
  "last_chunk_timestamp": "00:00:00",
  "second_speaker_at": null,

  "speaker_totals": {
    "therapist_seconds": 0,
    "client_seconds": 0,
    "client_talk_pct": 0
  },

  "utterance_counts": {
    "therapist_questions": 0,
    "therapist_sr": 0,
    "therapist_cr": 0,
    "rq_ratio": 0
  },

  "rolling_10m": {
    "window_start_timestamp": "00:00:00",
    "therapist_seconds": 0,
    "client_seconds": 0,
    "client_talk_pct": 0,
    "therapist_questions": 0,
    "therapist_sr": 0,
    "therapist_cr": 0,
    "rq_ratio": 0,
    "engagement_score": 0
  },

  "engagement": {
    "session_score": 0,
    "mean_client_words_per_turn": 0,
    "elaborated_turns": 0,
    "total_client_turns": 0
  },

  "therapist_agenda": [],
  "client_agenda": [],
  "people": [],
  "themes": [],

  "rupture": {
    "detected": false,
    "type": null,
    "chunk_index": null,
    "timestamp": null
  },

  "risk": {
    "flagged": false,
    "chunk_index": null,
    "timestamp": null
  }
}
```

Initialize `therapist_agenda` from `session_info.json` → `therapist_goals` (each goal becomes an item with status `not_discussed` and empty evidence).

Set `second_speaker_at` when the first client segment arrives — this marks the actual session start for timer purposes.

---

## Entity Map Substitution

At render time in the dashboard:

1. Read `entity_map.json` from the session folder
2. For any text containing `[CODE]` patterns, look up `CODE` in the mappings
3. Replace `[CODE]` with the real value for display
4. This applies to: transcript text, agenda evidence quotes, people names, theme phrases

Example:
- Stored: `"[PERSON_A] said I was being irrational"`
- Map: `{ "PERSON_A": "Jamie Smith" }`
- Displayed: `"Jamie Smith said I was being irrational"`

The entity map file is updated after each chunk as new entities are detected during the session.
