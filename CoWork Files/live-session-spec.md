# Live Session Dashboard — Measurement & Capture Specification
## 3 Big Things — Cowork Integration
### Version 2.0 — Locked

---

## Guiding principle

Every metric in the live dashboard is either:
- **Directly countable** from the transcript without AI (talk time, Q/SR/CR counts, engagement components)
- **AI-detected** per chunk (utterance classification, entity extraction, theme synthesis, agenda tracking, rupture signals)

Nothing is gestalt-scored live. Global ratings (Empathy, Warmth, Partnership etc.) belong to the post-session analysis tool only — they require full session view and are not appropriate for live display. The dashboard surfaces *process signals*, not *quality judgements*.

All metrics are consistent with the constructs used in post-session analysis (MITI 4.2.1, FIS-IS, Safran & Muran). Where a live metric is a proxy for a post-session construct, this is noted explicitly.

---

## Input contract

### Chunk files

JSON objects delivered to a watched folder on the local Mac. Nominally 60 seconds, soft-bounded at utterance end (58–65s acceptable). Pipeline must tolerate this variance and must not time-out expecting exactly 60 seconds.

```json
{
  "chunk_index": 4,
  "session_id": "JB_2026-03-17",
  "timestamp_start": "00:03:00",
  "timestamp_end": "00:04:02",
  "segments": [
    {
      "speaker": "therapist",
      "text": "So when [PERSON_1] said that, what came up for you?",
      "timestamp": "00:03:04"
    },
    {
      "speaker": "client",
      "text": "I just felt like I'd failed again. Like I always do.",
      "timestamp": "00:03:11"
    }
  ]
}
```

Chunks must be processed in chunk_index sequence. If a chunk arrives out of order, hold it until the preceding chunk has been processed.

### Session meta

Written once by the Swift app at session start:

```json
{
  "session_id": "JB_2026-03-17",
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

### Entity map

The Swift app holds the entity map in memory: `[PERSON_1] → real name`, `[LOCATION_1] → real place` etc. At session start, the Swift app passes the entity map to the Cowork dashboard webview as a local variable — no network, on-device only.

The dashboard substitutes real values at render time only. Real names and details are visible to the therapist on screen. All AI API calls receive redacted tokens only — real values never leave the Mac.

**Note:** Structure of how Swift passes the entity map to the Cowork webview (WKWebView injection, evaluateJavaScript, or localhost) to be determined with Swift developer.

### Redaction format

Entities appear as `[ENTITY_TYPE_N]` — e.g. `[PERSON_1]`, `[LOCATION_1]`, `[DATE_1]`, `[AGE_1]`. Consistent across all chunks via the Swift app's EntityMapping service.

### Session timer

Starts when the second person speaks — reflecting actual therapeutic time, not recording time. Duration passed from the Swift app via session meta.

---

## Section 1 — Session Progress Bar

Full width, sits at the very top of the dashboard. Always visible.

**Formula:**
```
progress_pct = elapsed_seconds / session_duration_seconds × 100
```

**Colour transitions:**
- Teal: > 12 minutes remaining
- Amber: 5–12 minutes remaining
- Red: < 5 minutes remaining

Remaining time displayed as `MM:SS remaining` in matching colour.

---

## Section 2 — Metrics Strip

Runs full width below the progress bar. Contains three gauges and two discrete indicators.

---

### 2.1 Client Talk %

**What it is:** Percentage of total speaking time attributed to the client.

**Formula:**
```
client_talk_pct = client_seconds / (client_seconds + therapist_seconds) × 100
```

**How captured:** Speaking duration estimated from word count × 0.4 seconds, or timestamp delta to next segment start where available. Accumulated across all chunks.

**Modes:**
- *Full session:* running total from timer start
- *Last 10 minutes:* rolling window

**Display:** Arc gauge. Colour zones directional only — no validated clinical threshold:
- Red: < 50%
- Amber: 50–64%
- Teal: ≥ 65%

**Post-session alignment:** Consistent with speaker_totals in Pass 1 and client elaboration inputs in Pass 2.

---

### 2.2 R:Q Ratio

**What it is:** Ratio of therapist reflections (simple + complex) to therapist questions. MITI 4.2.1 validated threshold: ≥ 2:1.

**Formula:**
```
rq_ratio = (simple_reflections + complex_reflections) / questions
```

Displayed as a ratio (e.g. 1.8:1), not a percentage. A clear 2:1 threshold marker is shown.

**Classification — per therapist utterance:**

- **Question (Q):** Any utterance formed as or functioning as a question, including embedded questions. Exclude rhetorical questions functioning as reflections.
- **Simple Reflection (SR):** Reflects back explicit content or surface emotion. Stays at the surface. Includes paraphrases and restatements that do not add meaning.
- **Complex Reflection (CR):** Adds meaning, pursues implication, reflects emotion beneath the surface, or goes beyond what the client explicitly stated. Includes double-sided reflections, underlying feeling reflections, metaphor-based reflections.
- **Other (O):** All other therapist utterances. Not counted in the ratio.

**Classification method:** AI per chunk.

**Modes:**
- *Full session:* cumulative from timer start
- *Last 10 minutes:* rolling window

**Display:** Ratio readout with 2:1 threshold marker:
- Red: < 1:1
- Amber: 1:1–1.9:1
- Teal: ≥ 2:1

**Note:** The 2:1 threshold applies to the working phase in post-session analysis. In the live dashboard, ratios will naturally be lower during opening and agenda phases. The therapist understands their own phase — the threshold line is reference, not alarm.

**Post-session alignment:** Directly consistent with Pass 1 R:Q counts. Identical SR/CR/Q definitions.

---

### 2.3 Client Engagement

**What it is:** Composite measure of how actively the client is engaging. Proxy for Client Engagement construct in post-session Pass 2.

**Formula:**
```
engagement_score = (talk_time_component × 0.5)
                 + (turn_length_component × 0.3)
                 + (elaboration_component × 0.2)
```

Where:
- `talk_time_component` = client_talk_pct (0–100)
- `turn_length_component` = min(mean_client_words_per_turn / 40 × 100, 100)
- `elaboration_component` = (elaborated_turns / total_client_turns) × 100
  - *Elaborated turn* = client segment with ≥ 3 sentences OR ≥ 40 words

All components calculable from transcript word counts and segment counts — no AI required.

**Modes:**
- *Full session:* all client segments from timer start
- *Last 10 minutes:* rolling window

**Display:** Arc gauge, 0–100. Colour zones directional only:
- Red: < 45
- Amber: 45–64
- Teal: ≥ 65

**Post-session alignment:** Consistent with client elaboration turns (Tier 3) and client-initiated content counts in Pass 2.

---

### 2.4 Rupture Signal (discrete indicator)

**What it is:** Flag indicating a potential alliance rupture. Based on Safran & Muran's rupture-repair model (FIS-IS Dimension 8, Pass 2).

Binary: off / detected. Not a severity scale.

**Two rupture types — both surface the same indicator:**

*Withdrawal rupture* — client moves away:
- Client turn length drops ≥ 40% from prior mean over 3+ consecutive turns after a period of elaboration
- Client emotional vocabulary drops markedly within a 2-chunk window
- Monosyllabic or minimal responses following substantive engagement
- Topic deflection: client redirects away from a topic the therapist has raised twice

*Confrontation rupture* — client moves against:
- Direct challenge to therapist's approach or framing
- Explicit expression of frustration with session direction
- Client repeats same content with increased emphasis after therapist has moved on

**Classification method:** AI per chunk, with lookback to prior 2 chunks. Withdrawal ruptures require cross-chunk comparison.

**Display:** Discrete indicator, visually separate from risk flag. Off: muted. Detected: amber border. Does not flash — a signal to note, not an emergency.

**Post-session alignment:** Direct proxy for Pass 2 rupture moment count and FIS-IS Dimension 8.

---

### 2.5 Risk Flag (discrete indicator)

**What it is:** Flag indicating language in a harm or crisis cluster detected in client speech only.

Not a clinical risk assessment. Confirms a signal was present — clinical judgement remains entirely with the therapist.

**Detection — client segments only:**
- Direct self-harm language
- Suicidal ideation language (explicit and implied)
- Harm to others language
- Crisis state indicators (hopelessness + finality language in combination)

**Classification method:** Rule-based pattern matching per chunk. Fast, no AI latency. Once raised, not cleared during session.

**Display:** Discrete indicator. Off: muted. Detected: red border. Clearly distinct from rupture signal. Persistent once raised.

**Primary value:** Documentation confirmation — records that the signal was present at a specific timestamp. Clinical, ACC, and medico-legal value.

**Post-session alignment:** Safety layer in both tools. Not a scored post-session domain.

---

## Section 3 — Agenda Panel (left column)

Two stacked lists: Therapist Focus and Client Agenda. Each item has a three-state status indicator and an expandable evidence dropdown.

### Status states

- ○ **Not discussed** — item identified but no substantive content yet
- ◑ **Partially discussed** — topic opened, evidence accumulating, not yet resolved
- ● **Fully discussed** — AI judges topic substantively addressed based on evidence weight

Transitions are one-directional: not discussed → partially → fully. No reversal. AI-assessed each chunk — no rule-based triggers.

---

### 3.1 Therapist Focus Topics

**Source:** `session_meta.json` → `therapist_goals`. Available from chunk one.

**Tracking:** Begins immediately from chunk one. No explicit agreement or trigger required. AI monitors all content for relevance to each goal from the start.

**Evidence:** Both verbatim quotes and AI-generated summaries. AI synthesises, enriches, and prunes continuously — no cap, AI owns quality and relevance. A summary gets richer as content accumulates rather than producing a growing list of fragments.

---

### 3.2 Client Agenda

**Source:** AI-detected from transcript. Not pre-populated. Can surface at any point in the session.

**Detection signal:** Explicit agreements or decisions to focus on a topic — client stating intent ("I want to talk about X") or therapist and client jointly landing on a focus. Passing mentions do not qualify.

**Confidence gate:** Candidate item must appear across ≥ 2 client turns before being added. Single-mention references not surfaced.

**Evidence:** Same model as therapist topics — AI synthesises and prunes continuously.

---

## Section 4 — Scratch Pad (right column)

### 4.1 People & Details

**What it captures:** Factual detail only. Not themes, not emotions, not interpretations. What a therapist would want to glance at to remember who's who and what's been happening.

**Captured from both speakers.**

**Types:**
- People — names (entity tokens, substituted to real names at render time), relationships, ages
- Locations — places of significance
- Key dates — significant past or upcoming dates
- Key events — named incidents or circumstances referenced in session

**Organisation:** AI groups connected information. Related details sit together:

> **[PERSON_1] — partner, age [AGE_1]**
> Lives in [LOCATION_1]. Key event: argument last week.

> **[PERSON_2] — mother**
> Visiting [DATE_1].

**Updates:** AI synthesises each chunk — enriching existing entries, connecting new details to existing people or events, pruning insignificant detail. Not append-only.

**Note:** Given redaction, detail will display as tokens until the entity map is passed from the Swift app. Build and review value in practice — feature may be simplified post-testing.

---

### 4.2 Themes

**What it captures:** Synthesised thematic content — what the session is actually about. Patterns, not topics.

**Target range:** 3–7 themes, aiming for ~5. Significance governs, not a hard count. A genuinely significant theme is never dropped to meet a ceiling. A weak theme is never retained to meet a floor.

**Every phrase must belong to a theme.** No unassigned phrases.

**Phrases are verbatim client language.** AI does not paraphrase them.

**Theme naming:** Short (2–5 words), synthesised, describing the underlying pattern not surface content.

**Per-chunk process:**

1. AI identifies candidate phrases from client speech — emotionally loaded, self-referential, or linguistically distinctive
2. Each phrase is either assigned to an existing theme (clear match) or generates a new theme
3. If a new theme would exceed 7:
   - AI compares significance of new theme against least significant existing theme
   - New theme more significant → replaces it; displaced phrases reassigned to closest remaining theme or dropped if no good fit
   - New theme not more significant → phrase assigned to closest existing theme
4. AI may rename, merge, or refine existing themes as patterns clarify across chunks

**Display:** Each theme is an expandable row. Expanding reveals nested verbatim phrases in client voice.

---

## Section 5 — Session State Schema

Lives in memory only. Discarded on session close. Never written to disk.

```json
{
  "session_id": "JB_2026-03-17",
  "session_type": "therapy",
  "session_start": "14:00:00",
  "session_duration_seconds": 3000,
  "chunks_processed": 7,
  "last_chunk_timestamp": "00:07:02",
  "second_speaker_at": "00:00:08",

  "speaker_totals": {
    "therapist_seconds": 280,
    "client_seconds": 560,
    "client_talk_pct": 66.7
  },

  "utterance_counts": {
    "therapist_questions": 14,
    "therapist_sr": 18,
    "therapist_cr": 12,
    "rq_ratio": 2.1
  },

  "rolling_10m": {
    "window_start_timestamp": "00:04:02",
    "therapist_seconds": 95,
    "client_seconds": 210,
    "client_talk_pct": 68.9,
    "therapist_questions": 5,
    "therapist_sr": 7,
    "therapist_cr": 6,
    "rq_ratio": 2.6,
    "engagement_score": 71
  },

  "engagement": {
    "session_score": 67,
    "mean_client_words_per_turn": 38,
    "elaborated_turns": 14,
    "total_client_turns": 22
  },

  "therapist_agenda": [
    {
      "id": "ta1",
      "text": "Explore sleep disruption patterns",
      "status": "fully_discussed",
      "evidence": [
        {
          "type": "summary",
          "text": "Waking at 3am, 4–5 nights per week — screen time and work rumination identified as triggers"
        },
        {
          "type": "quote",
          "text": "I just lie there waiting for it to be over",
          "timestamp": "00:04:22"
        }
      ]
    }
  ],

  "client_agenda": [
    {
      "id": "ca1",
      "text": "Argument with [PERSON_1] last week",
      "status": "partially_discussed",
      "evidence": [
        {
          "type": "quote",
          "text": "[PERSON_1] said I was being irrational and I just shut down",
          "timestamp": "00:06:14"
        }
      ]
    }
  ],

  "people": [
    {
      "token": "[PERSON_1]",
      "role": "partner",
      "details": {
        "age": "[AGE_1]",
        "location": "[LOCATION_1]"
      },
      "key_events": ["Argument last week"],
      "mentions": 6
    }
  ],

  "themes": [
    {
      "id": "th1",
      "text": "Self-blame as default",
      "phrases": [
        "I just can't seem to do anything right",
        "I always end up being the problem"
      ]
    },
    {
      "id": "th2",
      "text": "Shutdown under conflict",
      "phrases": [
        "[PERSON_1] said I was being irrational and I just shut down"
      ]
    }
  ],

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

---

## Section 6 — AI Analysis Prompt Contract

### Input per chunk

1. Chunk JSON (segments with speaker labels and timestamps)
2. Current session state (full object)
3. Therapist goals from session meta

### Output — delta only

AI returns only what has changed. Pipeline merges delta into session state. Dashboard reads from session state only.

```json
{
  "utterance_classifications": [
    { "timestamp": "00:03:04", "speaker": "therapist", "type": "CR" },
    { "timestamp": "00:03:18", "speaker": "therapist", "type": "Q" }
  ],

  "agenda_updates": [
    {
      "id": "ta1",
      "new_status": "fully_discussed",
      "evidence_action": "synthesise",
      "evidence_items": [
        {
          "type": "summary",
          "text": "Sleep hygiene discussed — screen time and work rumination identified as triggers"
        }
      ]
    }
  ],

  "new_client_agenda_items": [
    {
      "id": "ca2",
      "text": "Feeling overwhelmed at work",
      "confidence": "high"
    }
  ],

  "people_updates": [
    {
      "token": "[PERSON_1]",
      "role": "partner",
      "new_details": { "age": "[AGE_1]" },
      "new_events": ["Argument last week"]
    }
  ],

  "theme_updates": [
    {
      "action": "add_phrase",
      "theme_id": "th1",
      "phrase": "I always end up being the problem"
    },
    {
      "action": "new_theme",
      "theme": {
        "id": "th3",
        "text": "Avoidance under pressure",
        "phrases": ["I stayed late just to avoid dealing with it"]
      },
      "replaces": null
    }
  ],

  "rupture_signal": null,
  "risk_signal": null
}
```

**Theme delta actions:** `add_phrase`, `new_theme` (include `replaces: "th_id"` if displacing), `rename`, `merge`

**Evidence delta actions:** `append`, `synthesise` (replace with refined synthesis), `prune`

---

## Section 7 — Pipeline Architecture

1. **Folder watcher** — macOS FSEvents monitors chunk folder. On new file: read and parse JSON.
2. **Sequence check** — confirm chunk_index is next expected. Hold if gap detected.
3. **Local calculations** — update speaker totals, rolling window, engagement components from segment data. No AI.
4. **AI classification** — send chunk + session state to AI API. Receive delta JSON.
5. **State merge** — apply delta to session state.
6. **Dashboard push** — write updated session state to shared local file. Dashboard watches and re-renders.

**Communication:** Shared JSON state file on local filesystem. Pipeline writes on each chunk completion. Dashboard watches file and re-renders on change. All local, no networking.

---

## Section 8 — Explicitly excluded from live dashboard

- Global ratings (Empathy, Warmth, Partnership, CCT, SST) — require full session gestalt
- % Complex Reflections — not actionable live; post-session Pass 1 only
- Session phase tracking — therapist knows their phase; full/10m toggle provides needed context
- Affirm, SC, EA counts — too granular for live use; post-session Pass 1
- Change talk / sustain talk — require behaviour change context and full session view
- Derived globals (Relational Global, Technical Global) — synthesis constructs only

---

*Document status: LOCKED v2.0. Changes require review with Sean Versteegh before implementation.*
