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
  - `CoworkExportService.swift` — Saves redacted JSON chunks to Cowork-monitored folder
  - `SessionMetadata.swift` — Session info model (initials, type, goals, date, length)

The Lite target excludes full-app Views (MainContentView, phase views, session views), ViewModels (WorkflowViewModel, ImprovePhaseState), and AI services (SessionAssistantService, SessionAIService, LocalLLMService). It includes all audio/session/transcription services.

Lite includes WhisperKit, FluidAudio, and WebRTC dependencies. Uses `REDACTOR_LITE` compilation flag — `SessionManager.swift` uses `#if !REDACTOR_LITE` to skip Bedrock AI calls and post Cowork export notifications instead.

## Cowork Integration (Lite)

Live session recording saves redacted transcript chunks to a user-selected folder that Claude Cowork monitors.

**File output structure:**
```
{root_folder}/
  JB_2026-03-17_1430/
    session_info.json     ← metadata
    chunk_001.json        ← redacted transcript
    chunk_002.json
```

**Chunk JSON format:**
```json
{
  "chunk_index": 1,
  "timestamp_start": 60.0,
  "timestamp_end": 120.0,
  "segments": [
    { "speaker": "therapist", "text": "So [PERSON_1]...", "start": 60.5, "end": 63.2 },
    { "speaker": "client", "text": "[PERSON_1] has been...", "start": 64.0, "end": 67.8 }
  ]
}
```

Speaker labels: `therapist` (mic), `client` / `client_1`/`client_2` (auto-detected via diarization). Entity mapping ensures consistent `[PERSON_1]` codes across all chunks.

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
