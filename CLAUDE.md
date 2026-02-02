# Claude Code Notes for Redactor

## Build Instructions

**DO NOT run xcodebuild from CLI for this project.**

This app uses MLX (Metal Performance Shaders) which requires the full Xcode Metal toolchain. CLI builds will fail or cause DerivedData corruption.

**To verify builds:** Ask user to build from Xcode (Cmd+B) and share any error logs.

## Project Overview

Redactor is a macOS app for anonymizing clinical documentation. It detects and redacts PII (names, dates, locations, etc.) from healthcare documents.

## Key Technologies

- **MLX Swift** - Local LLM for PII review (requires Apple Silicon)
- **XLM-RoBERTa** - CoreML model for NER
- **AWS Bedrock** - Cloud AI via Lambda proxy (AU region)

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
