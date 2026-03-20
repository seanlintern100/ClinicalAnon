# Claude Code Notes for Redactor

## Build Instructions

```bash
# Full app (all features: AI analysis, live sessions, etc.)
xcodebuild -project Redactor.xcodeproj -scheme Redactor -configuration Debug build

# Lite app (redact + paste-back workflow, no AI/sessions)
xcodebuild -project Redactor.xcodeproj -scheme "Redactor Lite" -configuration Debug build
```

CLI builds via `xcodebuild` work. Use this to verify changes compile.
The project uses `xcodegen` — run `xcodegen generate` after editing `project.yml`.

## Project Overview

Redactor is a macOS app for anonymizing clinical documentation. It detects and redacts PII (names, dates, locations, etc.) from healthcare documents.

## Key Technologies

- **MLX Swift** - Local LLM for PII review (requires Apple Silicon)
- **XLM-RoBERTa** - CoreML model for NER
- **AWS Bedrock** - Cloud AI via Lambda proxy (AU region)

## Targets

- **Redactor** — Full-featured app with AI analysis (Bedrock), live sessions, transcription
- **Redactor Lite** — 3-panel paste-back workflow + live session recording with Cowork export. Shares all engine code (recognizers, entity mapping, overlap resolution) and session recording infrastructure with the full app.

Lite-specific files live in `ClinicalAnon/RedactorLite/`:
- `RedactorLiteApp.swift` — App entry point
- `LiteViewModel.swift` — Coordinates RedactPhaseState + restore + recording transfer
- `LiteRedactorView.swift` — 3-panel UI with entity sidebar
- `Recording/` — Live session recording with Cowork export:
  - `RecordingWindowController.swift` — Manages recording window
  - `RecordingWindowView.swift` — 3-panel recording layout (Setup | Transcript | Entities)
  - `SessionSetupPanel.swift` — Session metadata form + recording controls
  - `LiveTranscriptPanel.swift` — Auto-scrolling transcript with speaker labels
  - `SessionEntityPanel.swift` — Detected entities panel
  - `RecordingSettingsView.swift` — Transcription model, audio, export folder settings
  - `SessionExportService.swift` — Writes redacted chunks to Sessions/, entity maps to Private/
  - `SessionMetadata.swift` — Session info model (initials, type, goals, date, length)
  - `CopilotHTTPServer.swift` — HTTP server for MCP tool integration (port 8787)
  - `CopilotDashboardView.swift` — Native SwiftUI dashboard with arc gauges, entity substitution

The Lite target excludes full-app Views (MainContentView, phase views, session views), ViewModels (WorkflowViewModel, ImprovePhaseState), and AI services (SessionAssistantService, SessionAIService, LocalLLMService). It includes all audio/session/transcription services.

Lite includes WhisperKit, FluidAudio, and WebRTC dependencies. Uses `REDACTOR_LITE` compilation flag — `SessionManager.swift` uses `#if !REDACTOR_LITE` to skip Bedrock AI calls and post Cowork export notifications instead.

## Architecture: Core vs Copilot

Recording is CORE (always works standalone). AI analysis is an optional COPILOT layer.

**Core files** (no AI dependency): RecordingWindowView, SessionSetupPanel, LiveTranscriptPanel, SessionEntityPanel, SessionMetadata, RecordingSettingsView, FirstTimeSetupView, SessionExportService

**Copilot files** (walled off, can be compiled out): CopilotHTTPServer, CopilotDashboardView, MCP server (bundled resource)

**Coupling point:** One notification (`.transcriptionChunkRedacted`). Everything else is pluggable. Dashboard tab only appears when CopilotHTTPServer is running.

## Workspace Structure

App auto-creates workspace at `~/Library/Application Support/Redactor/Workspace/`:

```
Workspace/
  Sessions/                    ← Redacted data (Cowork reads via MCP)
    JB/
      2026-03-20_0937/
        session_info.json
        chunk_001.json         ← text uses [PERSON_A] codes
        session_state.json     ← AI writes analysis here via MCP
        .server_token
  Private/                     ← App only, AI CANNOT access
    JB/
      entity_map.json          ← [PERSON_A] → real names
  CoWork Files/                ← Cowork working folder
    .claude/skills/live-session/SKILL.md  ← auto-generated skill
    CLAUDE.md                  ← directs Cowork to use the skill
```

**Privacy model:** Entity maps with real names live in `Private/`. Cowork only sees redacted data in `Sessions/` via MCP tools. The dashboard reads from both locations to substitute codes back to real names for display only.

**IMPORTANT:** Entity codes MUST always use square brackets `[PERSON_A]` not bare `PERSON_A`. The dashboard `sub()` function handles both formats, but the SKILL.md instructs Cowork to always use brackets.

## Cowork Integration

Cowork connects via MCP server (`ClinicalAnon/Resources/CopilotMCP/redactor_mcp_server.py`).

**How instructions reach Cowork:**
1. `SessionExportService` writes `SKILL.md` to `CoWork Files/.claude/skills/live-session/` on app launch
2. `SessionExportService` writes `CLAUDE.md` to `CoWork Files/` directing Cowork to use the skill
3. User selects `CoWork Files/` as working folder in Cowork
4. Cowork discovers `/live-session` as a slash command from the skill
5. When user says "start a session", the skill provides the full MCP workflow

**MCP server config** (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "redactor": {
      "command": "<workspace>/.venv/bin/python3",
      "args": ["<path-to>/redactor_mcp_server.py"],
      "env": {
        "REDACTOR_EXPORT_ROOT": "<workspace>/Sessions"
      }
    }
  }
}
```

**MCP tools:** health_check, start_recording, stop_recording, pause_recording, resume_recording, get_session_info, get_session_state, get_new_chunks, write_session_state, is_session_complete

**DO NOT** add `get_entity_map` as an MCP tool — entity maps contain real names and must not be exposed to AI.

**HTTP server notes:**
- Starts in standby mode on app launch (only `/health` responds)
- `/start` endpoint is auth-free (creates the session and token)
- All other endpoints require token (query string or Authorization header)
- Body parsing accumulates TCP packets using Content-Length for reliable large POST bodies

## SKILL.md — How Cowork Gets Its Instructions

The app auto-generates `SKILL.md` at `CoWork Files/.claude/skills/live-session/SKILL.md` on launch. This is the **single source of truth** for Cowork's workflow. It contains:

- Session setup questions (initials, type, length, speakers, goals)
- MCP tool workflow (start_recording → poll loop → write_session_state → is_session_complete)
- Analysis rules (utterance classification Q/SR/CR/EX/O, agenda tracking, themes, people, rupture, risk)
- Entity code rules (always use `[BRACKETS]`)
- Therapist request handling (`therapist_request` field in session state)
- Coaching comment rules (strengths-based, one sentence per cycle)

**To modify Cowork's behaviour:** Edit the `writeSkillFile()` method in `SessionExportService.swift`, then re-run the app so it regenerates the file. Do NOT edit the workspace file directly — it gets overwritten on launch.

The app also writes `CLAUDE.md` to `CoWork Files/` root which directs Cowork to use the `/live-session` skill whenever the user says "start a session".

**There is no MCP prompt.** The MCP server (`redactor_mcp_server.py`) only provides tools, not workflow instructions. SKILL.md handles all workflow logic.

## Dashboard Interaction

The dashboard (`CopilotDashboardView.swift`) supports bidirectional communication with Cowork via `session_state.json`:

- **Coaching comment:** Cowork writes `coaching_comment` on every analysis cycle. Dashboard shows it in a teal bar. Strengths-based, not corrective.
- **Therapist request buttons:** Dashboard has extensible button array. Tapping writes `therapist_request` to `session_state.json`. Cowork reads it on next poll, responds in `therapist_request_response`, clears the request.
- **Adding new buttons:** Just add a string to the `requestButtons` array in `CopilotDashboardView`.

## Future: Clinical Notes (not yet implemented)

Planned: post-session clinical note generation triggered from Cowork or app button. Notes would be stored as `clinical_notes.json` in the session folder (redacted), with entity substitution at display/export time. New MCP tool `write_clinical_notes()` and `POST /notes` HTTP endpoint needed.

## Distribution (Lite)

```bash
# 1. Archive
xcodebuild -project Redactor.xcodeproj -scheme "Redactor Lite" -configuration Release archive \
  -archivePath /tmp/RedactorLite.xcarchive ARCHS=arm64 CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=5N8GXZGSZ5 "CODE_SIGN_IDENTITY=Developer ID Application"

# 2. Export (needs exportOptions.plist with method=developer-id, teamID=5N8GXZGSZ5)
xcodebuild -exportArchive -archivePath /tmp/RedactorLite.xcarchive \
  -exportPath /tmp/RedactorLiteExport -exportOptionsPlist /tmp/exportOptions.plist

# 3. Create & sign DMG
hdiutil create -volname "Redactor Lite" -srcfolder "/tmp/RedactorLiteExport/Redactor Lite.app" \
  -ov -format UDZO /tmp/RedactorLite.dmg
codesign --force --sign EFEE30A6ED0D62B8BB3970C39D09D1AFE0D1D474 /tmp/RedactorLite.dmg

# 4. Notarize & staple
xcrun notarytool submit /tmp/RedactorLite.dmg --keychain-profile "RedactorNotary" --wait
xcrun stapler staple /tmp/RedactorLite.dmg
```

Notarization keychain profile: `RedactorNotary` (Apple ID: sean.versteegh@gmail.com, Team: 5N8GXZGSZ5).
Signing cert hash: `EFEE30A6ED0D62B8BB3970C39D09D1AFE0D1D474` (use hash to avoid ambiguity with duplicate certs).

## Feature Branches

- `feature/gliner` - Preserved GLiNER code (removed from main, can be re-enabled by merging)

## Live Session Audio Capture

**IMPORTANT: Echo cancellation is REQUIRED for live sessions.**

When recording video calls (Zoom/Teams), the remote participant's voice plays through speakers and gets picked up by the microphone. Without echo cancellation, the remote voice is recorded TWICE:
1. Via system audio capture (clean, direct)
2. Via microphone (echo from speakers)

This ruins transcription with doubled/overlapping speech.

### Implementation

The app uses `VoiceProcessingAudioCapture.swift` which leverages Apple's `VoiceProcessingIO` AudioUnit directly (not AVAudioEngine's voice processing mode, which creates aggregate devices on macOS).

Key files:
- `AudioCaptureService.swift` - Main capture orchestration
- `VoiceProcessingAudioCapture.swift` - VoiceProcessingIO AudioUnit wrapper for echo cancellation

User setting: Settings > Transcription > Echo Cancellation (default: ON)

## Speaker Diarization

Uses **FluidAudio** (Apache 2.0, open source) for on-device speaker diarization via pyannote.

**Architecture:**
- WhisperKit → Transcription (keep existing, broad language support)
- FluidAudio → Speaker diarization (identifies "who spoke when" in system audio)
- Merge results by timestamp overlap

**Key files:**
- `SpeakerDiarizationService.swift` - FluidAudio wrapper using `OfflineDiarizerManager`
- `TranscriptSegment.swift` - `speakerId` and `speakerConfidence` fields
- `TranscriptView.swift` - Shows "Other A", "Other B" with color variation

**User setting:** Settings > Transcription > Enhanced Speaker Identification (default: OFF)

## Redaction Pipeline

### Entity Detection (Phase 1)

Entities come from multiple sources, combined in `RedactPhaseState.allEntities`:
- `result.entities` — Initial NER (Apple NER + XLM-RoBERTa)
- `customEntities` — User-added
- `piiReviewFindings` — Local LLM review
- `deepScanFindings` — Apple NER at lower confidence (0.75)

**Recognizer chain** (order matters, defined in `SwiftNERService.init()`):
EmailRecognizer → NZPhoneRecognizer → NZMedicalIDRecognizer → DateRecognizer → NZAddressRecognizer → MaoriNameRecognizer → RelationshipNameExtractor → TitleNameRecognizer → FirstNameDictionaryRecognizer → UserInclusionRecognizer → AppleNERRecognizer

### First Name Dictionary

`FirstNameDictionaryRecognizer` uses a 164K name dataset from [names.io](https://github.com/Debdut/names.io) (Apache 2.0) as a safety net for uncommon names (e.g., "Hamish") that NER models miss. Only matches capitalized words against the dictionary with common word / clinical term filtering.

Key files:
- `FirstNameDictionaryRecognizer.swift` — Recognizer (scans words, checks Set membership)
- `Resources/first_names.txt` — 164K lowercase first names, one per line
- `Resources/first_names_LICENSE.txt` — Apache 2.0 license

### Overlap Resolution

`RedactPhaseState.updateRedactedTextCache()` builds redacted text from entity positions. Overlap resolution uses a sweep algorithm with `maxEnd` tracking to avoid the chain-drop bug (where overlapping entities from different sources were silently lost).

### Restore (Phase 3)

`WorkflowViewModel.restoreNamesFromAIOutput()` re-registers entity mappings before restore. Uses first-write-wins (`hasMapping(forOriginalText:)` guard) to preserve redaction-phase mappings and avoid overwrites.
