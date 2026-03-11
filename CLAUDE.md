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
- **Redactor Lite** — Simplified 3-panel app for colleagues: Redact → Copy out → Paste back → Restore. No AI integration, no live sessions. Shares all engine code (recognizers, entity mapping, overlap resolution) with the full app.

Lite-specific files live in `ClinicalAnon/RedactorLite/`:
- `RedactorLiteApp.swift` — App entry point
- `LiteViewModel.swift` — Coordinates RedactPhaseState + restore
- `LiteRedactorView.swift` — 3-panel UI with entity sidebar

The Lite target excludes full-app Views (MainContentView, phase views, session views) and ViewModels (WorkflowViewModel, ImprovePhaseState) but shares everything else.

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
