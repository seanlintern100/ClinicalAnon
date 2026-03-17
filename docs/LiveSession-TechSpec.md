# Live Session Feature - Technical Specification

**Version:** 1.0
**Date:** February 2026
**Status:** Draft for Review

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Data Models](#3-data-models)
4. [Services](#4-services)
5. [Views & UI](#5-views--ui)
6. [Storage & Persistence](#6-storage--persistence)
7. [Audio Pipeline](#7-audio-pipeline)
8. [Transcription Pipeline](#8-transcription-pipeline)
9. [Live Redaction Pipeline](#9-live-redaction-pipeline)
10. [Session AI Integration](#10-session-ai-integration)
11. [Handoff to Redact Phase](#11-handoff-to-redact-phase)
12. [Export Functionality](#12-export-functionality)
13. [Deletion Flow](#13-deletion-flow)
14. [Error Handling](#14-error-handling)
15. [Permissions & Entitlements](#15-permissions--entitlements)
16. [File Structure](#16-file-structure)
17. [Implementation Phases](#17-implementation-phases)
18. [Testing Strategy](#18-testing-strategy)

---

## 1. Overview

### 1.1 Purpose

Extend Redactor with live meeting recording, on-device transcription, and real-time AI assistance while maintaining the core privacy guarantee: no unredacted clinical information leaves the device.

### 1.2 Key Capabilities

| Capability | Description |
|------------|-------------|
| Two-stream audio capture | Separate clinician (mic) and participant (system audio) streams |
| On-device transcription | WhisperKit with bundled `small` model, optional larger models |
| Live redaction | Incremental entity detection on 3-minute chunks |
| Session AI chat | Claude integration with redacted transcript context |
| Multi-session support | 5-7 sessions per day, batch processing at end of day |
| Crash recovery | Auto-save every chunk, restore on app relaunch |

### 1.3 Privacy Guarantees

- Audio files never leave the device
- Transcription runs entirely on-device (WhisperKit/Metal)
- Only redacted text is sent to Claude (via existing Bedrock pipeline)
- Session data deleted after handoff + user confirmation

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           ClinicalAnonApp                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      WorkflowViewModel                           │   │
│  │  - Existing redact/improve/restore phases                        │   │
│  │  - Receives handoff from SessionManager                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                     │
│                                    │ handoff                             │
│  ┌─────────────────────────────────┴───────────────────────────────┐   │
│  │                       SessionManager                             │   │
│  │  - Manages multiple LiveSession instances                        │   │
│  │  - Coordinates recording, transcription, redaction               │   │
│  │  - Handles persistence and recovery                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│           │              │              │              │                 │
│           ▼              ▼              ▼              ▼                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │AudioCapture  │ │Transcription │ │ LiveRedactor │ │ SessionAI    │   │
│  │Service       │ │Service       │ │              │ │ Service      │   │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘   │
│           │              │              │              │                 │
│           ▼              ▼              ▼              ▼                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│  │AVAudioEngine │ │ WhisperKit   │ │EntityMapping │ │BedrockService│   │
│  │ScreenCapture │ │              │ │(existing)    │ │(existing)    │   │
│  │Kit           │ │              │ │              │ │              │   │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `SessionManager` | Lifecycle management for all sessions, persistence, recovery |
| `LiveSession` | State container for a single recording session |
| `AudioCaptureService` | Two-stream audio capture and chunk writing |
| `TranscriptionService` | WhisperKit integration, chunk processing |
| `LiveRedactor` | Incremental entity detection, EntityMapping coordination |
| `SessionAIService` | Chat interface, context management, Bedrock integration |
| `SessionStorageService` | Encrypted file I/O, auto-save, recovery |

### 2.3 Reused Components

| Existing Component | Usage in Live Session |
|--------------------|----------------------|
| `EntityMapping` | Entity consistency across transcript chunks |
| `ConversationContext` | AI chat history and context management |
| `BedrockService` | Claude API calls for session AI |
| `AnonymizationEngine` | Entity detection (incremental mode) |
| `Entity`, `EntityType` | Data models for detected entities |

---

## 3. Data Models

### 3.1 LiveSession

Primary state container for a recording session.

```swift
/// Represents a single live recording session
/// File: ClinicalAnon/Models/LiveSession.swift

import Foundation

enum SessionState: String, Codable {
    case recording      // Audio capture active
    case paused         // Capture paused, can resume
    case complete       // Recording stopped, awaiting handoff
    case handedOff      // Transferred to Redact phase
}

@MainActor
class LiveSession: ObservableObject, Identifiable, Codable {

    // MARK: - Identity

    let id: UUID
    let createdAt: Date

    // MARK: - State

    @Published var state: SessionState
    @Published var name: String                    // User-editable, auto-timestamp initially

    // MARK: - Timing

    @Published var recordingDuration: TimeInterval // Total recording time (excludes pauses)
    @Published var pausedAt: Date?                 // When pause started (nil if not paused)
    private var pauseGaps: [(start: Date, end: Date)] = []

    // MARK: - Transcript

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var lastTranscriptUpdate: Date?

    // MARK: - Entities

    @Published var entityMapping: EntityMapping
    @Published var detectedEntities: [Entity] = []

    // MARK: - AI Chat

    @Published var conversationContext: ConversationContext
    @Published var chatMessages: [ChatMessage] = []

    // MARK: - Audio References

    var audioChunkPaths: [AudioChunkReference] = []

    // MARK: - Computed Properties

    var displayName: String {
        name.isEmpty ? formattedTimestamp : name
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "Session – \(formatter.string(from: createdAt))"
    }

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Full raw transcript (unredacted) for handoff
    var rawTranscript: String {
        transcriptSegments
            .sorted { $0.startTime < $1.startTime }
            .map { "[\($0.speaker.label)] \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// Redacted transcript for AI context
    var redactedTranscript: String {
        // Apply entityMapping to rawTranscript
        var result = rawTranscript
        for entity in detectedEntities.sorted(by: {
            ($0.positions.first?.first ?? 0) > ($1.positions.first?.first ?? 0)
        }) {
            result = result.replacingOccurrences(
                of: entity.originalText,
                with: entity.replacementCode,
                options: .caseInsensitive
            )
        }
        return result
    }

    // MARK: - Initialization

    init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = Date()
        self.state = .recording
        self.name = ""
        self.recordingDuration = 0
        self.entityMapping = EntityMapping()
        self.conversationContext = ConversationContext()
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, createdAt, state, name, recordingDuration
        case transcriptSegments, detectedEntities, audioChunkPaths
        case pauseGaps
    }

    // Custom encoding/decoding for @Published and non-Codable types
    // Implementation details omitted for brevity
}
```

### 3.2 TranscriptSegment

Represents a chunk of transcribed speech.

```swift
/// A segment of transcribed speech with timing and speaker info
/// File: ClinicalAnon/Models/TranscriptSegment.swift

import Foundation

enum Speaker: String, Codable {
    case clinician = "Clinician"
    case other = "Other"

    var label: String { rawValue }
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let startTime: TimeInterval      // Seconds from session start
    let endTime: TimeInterval
    let chunkIndex: Int              // Which audio chunk this came from
    let confidence: Double?          // Whisper confidence (0-1)

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        chunkIndex: Int,
        confidence: Double? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.chunkIndex = chunkIndex
        self.confidence = confidence
    }

    /// Formatted timestamp for display (e.g., "12:34")
    var formattedStartTime: String {
        let minutes = Int(startTime) / 60
        let seconds = Int(startTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

### 3.3 AudioChunkReference

Tracks audio files on disk.

```swift
/// Reference to an audio chunk file on disk
/// File: ClinicalAnon/Models/AudioChunkReference.swift

import Foundation

enum AudioStream: String, Codable {
    case microphone = "mic"
    case system = "sys"
}

struct AudioChunkReference: Identifiable, Codable, Hashable {
    let id: UUID
    let stream: AudioStream
    let chunkIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let filePath: String              // Relative to session directory
    let fileSize: Int64               // Bytes
    let isProcessed: Bool             // Has transcription completed?

    var fileName: String {
        "\(stream.rawValue)_\(String(format: "%03d", chunkIndex)).m4a"
    }
}
```

### 3.4 TranscriptionGap

Represents a gap in transcription (pause or failure).

```swift
/// Represents a gap in the transcript
/// File: ClinicalAnon/Models/TranscriptionGap.swift

import Foundation

enum GapReason: String, Codable {
    case paused = "Paused"
    case transcriptionFailed = "Transcription failed"
    case audioCorrupted = "Audio corrupted"
}

struct TranscriptionGap: Identifiable, Codable {
    let id: UUID
    let reason: GapReason
    let startTime: TimeInterval
    let endTime: TimeInterval
    let chunkIndex: Int?              // Which chunk failed (nil for pauses)
    let canRetry: Bool                // Can user retry with larger model?

    var displayText: String {
        let startFormatted = formatTime(startTime)
        let endFormatted = formatTime(endTime)
        return "[Gap: \(startFormatted) – \(endFormatted) – \(reason.rawValue)]"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
```

---

## 4. Services

### 4.1 SessionManager

Central coordinator for all live sessions.

```swift
/// Manages all live recording sessions
/// File: ClinicalAnon/Services/Session/SessionManager.swift

import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SessionManager()

    // MARK: - Published State

    @Published private(set) var sessions: [LiveSession] = []
    @Published private(set) var activeSession: LiveSession?
    @Published private(set) var isRestoring: Bool = false

    // MARK: - Services

    private let audioCaptureService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private let liveRedactor: LiveRedactor
    private let storageService: SessionStorageService

    // MARK: - Initialization

    private init() {
        self.audioCaptureService = AudioCaptureService()
        self.transcriptionService = TranscriptionService()
        self.liveRedactor = LiveRedactor()
        self.storageService = SessionStorageService()

        // Restore sessions on init
        Task {
            await restoreSessionsOnLaunch()
        }
    }

    // MARK: - Session Lifecycle

    /// Start a new recording session
    func startSession() async throws -> LiveSession {
        let session = LiveSession()
        sessions.append(session)
        activeSession = session

        // Create session directory
        try storageService.createSessionDirectory(for: session)

        // Start audio capture
        try await audioCaptureService.startCapture(for: session)

        // Start transcription pipeline
        transcriptionService.startProcessing(for: session) { [weak self] segment in
            self?.handleNewSegment(segment, for: session)
        }

        return session
    }

    /// Pause the active session
    func pauseSession(_ session: LiveSession) {
        guard session.state == .recording else { return }

        session.state = .paused
        session.pausedAt = Date()

        audioCaptureService.pauseCapture(for: session)

        // Process any pending audio before pause takes effect
        transcriptionService.flushPendingChunk(for: session)

        // Add pause marker to transcript
        let pauseGap = TranscriptionGap(
            id: UUID(),
            reason: .paused,
            startTime: session.recordingDuration,
            endTime: session.recordingDuration, // Will be updated on resume
            chunkIndex: nil,
            canRetry: false
        )
        // Store gap reference for updating on resume
    }

    /// Resume a paused session
    func resumeSession(_ session: LiveSession) async throws {
        guard session.state == .paused else { return }

        session.state = .recording
        session.pausedAt = nil

        try await audioCaptureService.resumeCapture(for: session)
        transcriptionService.resumeProcessing(for: session)
    }

    /// Stop recording and mark session complete
    func stopSession(_ session: LiveSession) async {
        guard session.state == .recording || session.state == .paused else { return }

        // Stop audio capture
        audioCaptureService.stopCapture(for: session)

        // Process final chunk
        await transcriptionService.processFinalChunk(for: session)

        // Run final entity detection pass
        await liveRedactor.runFinalPass(for: session)

        session.state = .complete

        // Save final state
        try? await storageService.saveSession(session)

        if activeSession?.id == session.id {
            activeSession = nil
        }

        // Trigger session naming prompt (see SessionNamePromptView)
        NotificationCenter.default.post(
            name: .sessionNeedsNaming,
            object: session.id
        )
    }

    /// Hand off session to Redact phase
    /// Note: Session remains visible in sidebar with "In Redact" state until deletion is confirmed
    func handoffToRedact(_ session: LiveSession) -> String {
        guard session.state == .complete else {
            fatalError("Cannot handoff session that is not complete")
        }

        session.state = .handedOff

        // DO NOT remove from sessions list yet
        // Session stays visible (greyed out, "In Redact" state) until deletion is confirmed
        // This ensures the deletion prompt fires even if app crashes during Redact phase

        // Save state change
        Task {
            try? await storageService.saveSession(session)
        }

        // Return raw transcript for Redact phase
        return session.rawTranscript
    }

    /// Delete a session and all associated data
    func deleteSession(_ session: LiveSession) async {
        sessions.removeAll { $0.id == session.id }

        if activeSession?.id == session.id {
            activeSession = nil
        }

        await storageService.deleteSession(session)
    }

    // MARK: - Recovery

    /// Restore sessions from disk on app launch
    private func restoreSessionsOnLaunch() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            let restoredSessions = try await storageService.loadAllSessions()

            for session in restoredSessions {
                // Sessions that were recording when app crashed become complete
                if session.state == .recording || session.state == .paused {
                    session.state = .complete
                }
                sessions.append(session)
            }

            if !restoredSessions.isEmpty {
                // Notify user of recovered sessions
                NotificationCenter.default.post(
                    name: .sessionsRecovered,
                    object: restoredSessions.count
                )
            }
        } catch {
            print("Failed to restore sessions: \(error)")
        }
    }

    // MARK: - Internal Handlers

    private func handleNewSegment(_ segment: TranscriptSegment, for session: LiveSession) {
        session.transcriptSegments.append(segment)
        session.lastTranscriptUpdate = Date()

        // Trigger incremental entity detection
        Task {
            await liveRedactor.processNewSegment(segment, for: session)
        }

        // Auto-save
        Task {
            try? await storageService.saveSession(session)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let sessionsRecovered = Notification.Name("sessionsRecovered")
    static let sessionNeedsNaming = Notification.Name("sessionNeedsNaming")
}
```

### 4.2 AudioCaptureService

Handles two-stream audio capture.

```swift
/// Captures audio from microphone and system audio
/// File: ClinicalAnon/Services/Session/AudioCaptureService.swift

import Foundation
import AVFoundation
import ScreenCaptureKit

@MainActor
class AudioCaptureService: ObservableObject {

    // MARK: - Configuration

    private let chunkDuration: TimeInterval = 180    // 3 minutes
    private let overlapDuration: TimeInterval = 30   // 30 seconds (intentionally longer than 15s for better transcription continuity)
    private let sampleRate: Double = 16000           // WhisperKit expects 16kHz
    private let channels: AVAudioChannelCount = 1    // Mono

    // MARK: - Timestamp Synchronization

    /// Shared start time for both audio streams to ensure alignment
    private var sessionStartTime: Date?

    // MARK: - State

    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0

    // MARK: - Audio Engine

    private var microphoneEngine: AVAudioEngine?
    private var systemAudioStream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?

    // MARK: - File Writers

    private var microphoneWriter: AVAssetWriter?
    private var systemWriter: AVAssetWriter?
    private var currentChunkIndex: Int = 0
    private var chunkStartTime: Date?

    // MARK: - Session Reference

    private weak var currentSession: LiveSession?

    // MARK: - Public Methods

    func startCapture(for session: LiveSession) async throws {
        currentSession = session
        currentChunkIndex = 0

        // Capture shared start time BEFORE any stream setup
        // This ensures both streams have identical reference point
        sessionStartTime = Date()

        // Request permissions if needed
        try await requestPermissions()

        // Start microphone capture
        try setupMicrophoneCapture(for: session)

        // Start system audio capture
        try await setupSystemAudioCapture(for: session)

        // Start first chunk
        try startNewChunk(for: session)

        isCapturing = true
    }

    func pauseCapture(for session: LiveSession) {
        // Finish current chunk
        finishCurrentChunk(for: session)

        microphoneEngine?.pause()
        systemAudioStream?.stopCapture()

        isCapturing = false
    }

    func resumeCapture(for session: LiveSession) async throws {
        try startNewChunk(for: session)

        try microphoneEngine?.start()
        try systemAudioStream?.startCapture()

        isCapturing = true
    }

    func stopCapture(for session: LiveSession) {
        finishCurrentChunk(for: session)

        microphoneEngine?.stop()
        microphoneEngine = nil

        systemAudioStream?.stopCapture()
        systemAudioStream = nil

        isCapturing = false
    }

    // MARK: - Private Methods

    private func requestPermissions() async throws {
        // Microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw AudioCaptureError.microphonePermissionDenied
            }
        } else if micStatus == .denied {
            throw AudioCaptureError.microphonePermissionDenied
        }

        // Screen recording permission (for system audio)
        // ScreenCaptureKit will prompt automatically on first use
    }

    private func setupMicrophoneCapture(for session: LiveSession) throws {
        microphoneEngine = AVAudioEngine()

        guard let engine = microphoneEngine else {
            throw AudioCaptureError.engineSetupFailed
        }

        let inputNode = engine.inputNode
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            self?.handleMicrophoneBuffer(buffer, time: time)
        }

        try engine.start()
    }

    private func setupSystemAudioCapture(for session: LiveSession) async throws {
        // Get available content to capture
        let content = try await SCShareableContent.current

        // Create filter to exclude our own app
        let excludedApps = content.applications.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        let filter = SCContentFilter(
            display: content.displays.first!,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        // Configure for audio only
        streamConfiguration = SCStreamConfiguration()
        streamConfiguration?.capturesAudio = true
        streamConfiguration?.excludesCurrentProcessAudio = true
        streamConfiguration?.sampleRate = Int(sampleRate)
        streamConfiguration?.channelCount = Int(channels)

        // We only need audio, minimize video capture
        streamConfiguration?.width = 2
        streamConfiguration?.height = 2
        streamConfiguration?.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        systemAudioStream = SCStream(
            filter: filter,
            configuration: streamConfiguration!,
            delegate: nil
        )

        try systemAudioStream?.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "system-audio-queue")
        )

        try await systemAudioStream?.startCapture()
    }

    private func startNewChunk(for session: LiveSession) throws {
        chunkStartTime = Date()

        let sessionDir = SessionStorageService.sessionDirectory(for: session)

        // Microphone writer
        let micURL = sessionDir
            .appendingPathComponent("audio")
            .appendingPathComponent("mic_\(String(format: "%03d", currentChunkIndex)).m4a")
        microphoneWriter = try createAssetWriter(url: micURL)

        // System audio writer
        let sysURL = sessionDir
            .appendingPathComponent("audio")
            .appendingPathComponent("sys_\(String(format: "%03d", currentChunkIndex)).m4a")
        systemWriter = try createAssetWriter(url: sysURL)

        // Schedule chunk rotation
        scheduleChunkRotation(for: session)
    }

    private func finishCurrentChunk(for session: LiveSession) {
        guard let startTime = chunkStartTime else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Finish writing
        microphoneWriter?.finishWriting { }
        systemWriter?.finishWriting { }

        // Record chunk references
        let micChunk = AudioChunkReference(
            id: UUID(),
            stream: .microphone,
            chunkIndex: currentChunkIndex,
            startTime: session.recordingDuration,
            endTime: session.recordingDuration + duration,
            filePath: "audio/mic_\(String(format: "%03d", currentChunkIndex)).m4a",
            fileSize: 0, // Will be calculated
            isProcessed: false
        )

        let sysChunk = AudioChunkReference(
            id: UUID(),
            stream: .system,
            chunkIndex: currentChunkIndex,
            startTime: session.recordingDuration,
            endTime: session.recordingDuration + duration,
            filePath: "audio/sys_\(String(format: "%03d", currentChunkIndex)).m4a",
            fileSize: 0,
            isProcessed: false
        )

        session.audioChunkPaths.append(micChunk)
        session.audioChunkPaths.append(sysChunk)
        session.recordingDuration += duration

        currentChunkIndex += 1
    }

    private func scheduleChunkRotation(for session: LiveSession) {
        DispatchQueue.main.asyncAfter(deadline: .now() + chunkDuration) { [weak self] in
            guard let self = self, self.isCapturing else { return }

            self.finishCurrentChunk(for: session)

            // Notify transcription service
            NotificationCenter.default.post(
                name: .audioChunkReady,
                object: (session.id, self.currentChunkIndex - 1)
            )

            do {
                try self.startNewChunk(for: session)
            } catch {
                print("Failed to start new chunk: \(error)")
            }
        }
    }

    private func createAssetWriter(url: URL) throws -> AVAssetWriter {
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(url: url, fileType: .m4a)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128000
        ]

        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: settings
        )
        input.expectsMediaDataInRealTime = true

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        return writer
    }

    private func handleMicrophoneBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Calculate level for UI meter
        if let channelData = buffer.floatChannelData?[0] {
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += abs(channelData[i])
            }
            let average = sum / Float(frameCount)
            DispatchQueue.main.async {
                self.microphoneLevel = average
            }
        }

        // Write to file
        // (Implementation details for AVAssetWriter input)
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureService: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }

        // Write to system audio file
        // (Implementation details)
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case engineSetupFailed
    case writerSetupFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required for recording"
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required to capture meeting audio"
        case .engineSetupFailed:
            return "Failed to initialize audio engine"
        case .writerSetupFailed:
            return "Failed to create audio file writer"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioChunkReady = Notification.Name("audioChunkReady")
}
```

### 4.3 TranscriptionService

Manages WhisperKit transcription pipeline.

```swift
/// Handles on-device transcription using WhisperKit
/// File: ClinicalAnon/Services/Session/TranscriptionService.swift

import Foundation
import WhisperKit

@MainActor
class TranscriptionService: ObservableObject {

    // MARK: - Configuration

    private let overlapDuration: TimeInterval = 30   // 30 seconds (intentionally longer than 15s for better transcription continuity)

    // MARK: - State

    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var currentModel: WhisperModel = .small
    @Published private(set) var processingProgress: Double = 0

    // MARK: - WhisperKit

    private var whisperKit: WhisperKit?

    // MARK: - Processing State

    private var processingQueue: [(sessionId: UUID, chunkIndex: Int)] = []
    private var segmentCallbacks: [UUID: (TranscriptSegment) -> Void] = [:]
    private var lastSegmentEndTimes: [UUID: TimeInterval] = [:]

    // MARK: - Initialization

    init() {
        // Listen for audio chunk ready notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChunkReady),
            name: .audioChunkReady,
            object: nil
        )
    }

    // MARK: - Model Management

    enum WhisperModel: String, CaseIterable {
        case small = "openai/whisper-small"
        case medium = "openai/whisper-medium"
        case large = "openai/whisper-large-v3"

        var displayName: String {
            switch self {
            case .small: return "Small (Fast)"
            case .medium: return "Medium (Balanced)"
            case .large: return "Large (Accurate)"
            }
        }

        var approximateSize: String {
            switch self {
            case .small: return "~400 MB"
            case .medium: return "~1.5 GB"
            case .large: return "~3 GB"
            }
        }

        var approximateRAM: String {
            switch self {
            case .small: return "~1 GB"
            case .medium: return "~2 GB"
            case .large: return "~3.5 GB"
            }
        }
    }

    func loadModel(_ model: WhisperModel = .small) async throws {
        isProcessing = true
        defer { isProcessing = false }

        whisperKit = try await WhisperKit(
            model: model.rawValue,
            computeOptions: .init(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndGPU)
        )

        currentModel = model
        isModelLoaded = true
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }

    // MARK: - Processing Control

    func startProcessing(
        for session: LiveSession,
        onSegment: @escaping (TranscriptSegment) -> Void
    ) {
        segmentCallbacks[session.id] = onSegment
        lastSegmentEndTimes[session.id] = 0
    }

    func stopProcessing(for session: LiveSession) {
        segmentCallbacks.removeValue(forKey: session.id)
        lastSegmentEndTimes.removeValue(forKey: session.id)
    }

    func flushPendingChunk(for session: LiveSession) {
        // Process any audio that hasn't been chunked yet
        // (For pause scenario)
    }

    func resumeProcessing(for session: LiveSession) {
        // Resume after pause - no special handling needed
        // Next chunk will be processed normally
    }

    func processFinalChunk(for session: LiveSession) async {
        // Process any remaining audio after stop
        // Wait for all pending transcriptions to complete
        while processingQueue.contains(where: { $0.sessionId == session.id }) {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    // MARK: - Chunk Processing

    @objc private func handleChunkReady(_ notification: Notification) {
        guard let (sessionId, chunkIndex) = notification.object as? (UUID, Int) else { return }

        processingQueue.append((sessionId, chunkIndex))
        processNextChunk()
    }

    private func processNextChunk() {
        guard !isProcessing, let next = processingQueue.first else { return }

        processingQueue.removeFirst()

        Task {
            await processChunk(sessionId: next.sessionId, chunkIndex: next.chunkIndex)
            processNextChunk()
        }
    }

    private func processChunk(sessionId: UUID, chunkIndex: Int) async {
        guard let whisperKit = whisperKit else {
            // Model not loaded - queue for later or fail
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        // Get audio file paths
        let sessionDir = SessionStorageService.sessionDirectory(forId: sessionId)
        let micPath = sessionDir
            .appendingPathComponent("audio")
            .appendingPathComponent("mic_\(String(format: "%03d", chunkIndex)).m4a")
        let sysPath = sessionDir
            .appendingPathComponent("audio")
            .appendingPathComponent("sys_\(String(format: "%03d", chunkIndex)).m4a")

        // Get actual chunk timing from stored AudioChunkReference
        // This handles pauses correctly (don't assume continuous recording)
        let chunkStartTime = await getActualChunkStartTime(sessionId: sessionId, chunkIndex: chunkIndex)

        // Process microphone audio
        do {
            let micSegments = try await transcribeAudio(
                at: micPath,
                speaker: .clinician,
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime
            )

            // Deliver segments
            if let callback = segmentCallbacks[sessionId] {
                for segment in micSegments {
                    callback(segment)
                }
            }
        } catch {
            // Create gap marker for failed transcription
            handleTranscriptionFailure(
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime,
                error: error
            )
        }

        // Process system audio
        do {
            let sysSegments = try await transcribeAudio(
                at: sysPath,
                speaker: .other,
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime
            )

            if let callback = segmentCallbacks[sessionId] {
                for segment in sysSegments {
                    callback(segment)
                }
            }
        } catch {
            handleTranscriptionFailure(
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                chunkStartTime: chunkStartTime,
                error: error
            )
        }
    }

    private func transcribeAudio(
        at url: URL,
        speaker: Speaker,
        chunkIndex: Int,
        chunkStartTime: TimeInterval
    ) async throws -> [TranscriptSegment] {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Transcribe with WhisperKit
        let result = try await whisperKit.transcribe(
            audioPath: url.path,
            decodeOptions: .init(
                language: "en",
                task: .transcribe,
                temperatureFallbackCount: 3
            )
        )

        // Convert WhisperKit segments to our TranscriptSegment
        var segments: [TranscriptSegment] = []

        for whisperSegment in result.segments {
            let segment = TranscriptSegment(
                speaker: speaker,
                text: whisperSegment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: chunkStartTime + whisperSegment.start,
                endTime: chunkStartTime + whisperSegment.end,
                chunkIndex: chunkIndex,
                confidence: Double(whisperSegment.avgLogprob)
            )
            segments.append(segment)
        }

        return segments
    }

    private func handleTranscriptionFailure(
        sessionId: UUID,
        chunkIndex: Int,
        chunkStartTime: TimeInterval,
        error: Error
    ) {
        // Create gap marker
        let gap = TranscriptionGap(
            id: UUID(),
            reason: .transcriptionFailed,
            startTime: chunkStartTime,
            endTime: chunkStartTime + 180, // Assume full chunk duration
            chunkIndex: chunkIndex,
            canRetry: true
        )

        // Notify via callback as a special segment type
        // (UI will display gap marker)

        print("Transcription failed for chunk \(chunkIndex): \(error)")
    }

    // MARK: - Retry Failed Chunk

    func retryChunk(
        sessionId: UUID,
        chunkIndex: Int,
        withModel model: WhisperModel? = nil
    ) async throws {
        // Optionally load a different model
        if let model = model, model != currentModel {
            try await loadModel(model)
        }

        // Re-process the chunk
        await processChunk(sessionId: sessionId, chunkIndex: chunkIndex)
    }

    // MARK: - Timing Helpers

    /// Get actual chunk start time from stored AudioChunkReference
    /// This handles pauses correctly instead of assuming continuous recording
    private func getActualChunkStartTime(sessionId: UUID, chunkIndex: Int) async -> TimeInterval {
        do {
            let session = try await SessionStorageService().loadSession(id: sessionId)
            if let chunk = session.audioChunkPaths.first(where: {
                $0.chunkIndex == chunkIndex && $0.stream == .microphone
            }) {
                return chunk.startTime
            }
        } catch {
            print("Failed to get actual chunk timing, falling back to estimate")
        }

        // Fallback: estimate based on chunk index (may be inaccurate with pauses)
        return TimeInterval(chunkIndex) * 180
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioFileNotFound
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .audioFileNotFound:
            return "Audio file not found"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
```

### 4.4 LiveRedactor

Incremental entity detection for live transcripts.

```swift
/// Performs incremental entity detection on live transcripts
/// File: ClinicalAnon/Services/Session/LiveRedactor.swift

import Foundation

@MainActor
class LiveRedactor: ObservableObject {

    // MARK: - Dependencies

    private let anonymizationEngine: AnonymizationEngine

    // MARK: - State

    @Published private(set) var isProcessing: Bool = false

    // MARK: - Initialization

    init() {
        self.anonymizationEngine = AnonymizationEngine()
    }

    // MARK: - Incremental Processing

    /// Process a new transcript segment and detect entities
    func processNewSegment(_ segment: TranscriptSegment, for session: LiveSession) async {
        isProcessing = true
        defer { isProcessing = false }

        // Build text from just this segment
        let segmentText = "[\(segment.speaker.label)] \(segment.text)"

        do {
            // Run entity detection on new segment
            let result = try await anonymizationEngine.anonymize(
                text: segmentText,
                existingMapping: session.entityMapping
            )

            // Merge new entities into session
            for entity in result.entities {
                // Check if this entity already exists
                if !session.detectedEntities.contains(where: {
                    $0.originalText.lowercased() == entity.originalText.lowercased()
                }) {
                    session.detectedEntities.append(entity)
                }
            }

            // EntityMapping is updated in-place by anonymizationEngine

        } catch {
            print("Live redaction failed for segment: \(error)")
            // Continue without failing - segment is still added to transcript
        }
    }

    /// Run a final pass over the complete transcript
    func runFinalPass(for session: LiveSession) async {
        isProcessing = true
        defer { isProcessing = false }

        // Get full transcript
        let fullText = session.rawTranscript

        do {
            // Run detection on full text for consistency
            let result = try await anonymizationEngine.anonymize(
                text: fullText,
                existingMapping: session.entityMapping
            )

            // Replace entities with final detection
            session.detectedEntities = result.entities

        } catch {
            print("Final redaction pass failed: \(error)")
        }
    }
}
```

### 4.5 SessionAIService

Handles AI chat with transcript context.

```swift
/// Provides AI chat functionality for live sessions
/// File: ClinicalAnon/Services/Session/SessionAIService.swift

import Foundation

@MainActor
class SessionAIService: ObservableObject {

    // MARK: - Configuration

    private let maxContextTokens = 10000  // Approximate token limit for context
    private let tokensPerWord = 1.3       // Rough estimate

    // MARK: - Dependencies

    private let bedrockService: BedrockService

    // MARK: - State

    @Published private(set) var isProcessing: Bool = false
    @Published var includeTranscriptContext: Bool = true

    // MARK: - Initialization

    init(bedrockService: BedrockService) {
        self.bedrockService = bedrockService
    }

    // MARK: - Chat

    /// Send a message with optional transcript context
    func sendMessage(
        _ message: String,
        session: LiveSession,
        model: String
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        // Add user message to conversation
        session.conversationContext.addUserMessage(message)

        // Build system prompt
        var systemPrompt = """
        You are a clinical psychology AI assistant helping a clinician during a therapy session.

        Your role is to:
        - Provide therapeutic insights and suggestions
        - Summarize key points from the conversation
        - Suggest relevant questions or approaches
        - Maintain professional clinical language

        Important:
        - All client information has been redacted (shown as [CLIENT_A], [DATE_A], etc.)
        - Never attempt to guess or reveal redacted information
        - Focus on therapeutic content, not identifying details
        """

        // Add transcript context if enabled
        if includeTranscriptContext {
            let contextText = prepareTranscriptContext(for: session)
            if !contextText.isEmpty {
                systemPrompt += """


                ## Current Session Transcript (Redacted)
                \(contextText)
                """
            }
        }

        // Build with conversation context
        let finalSystemPrompt = session.conversationContext.buildSystemPrompt(
            basePrompt: systemPrompt
        )

        // Get messages for API
        let messages = session.conversationContext.getMessagesForAPI()

        // Call Bedrock
        let response = try await bedrockService.invoke(
            systemPrompt: finalSystemPrompt,
            messages: messages,
            model: model,
            maxTokens: 2048
        )

        // Add assistant response to conversation
        session.conversationContext.addAssistantMessage(response)

        // Also store in session's chat messages for UI
        session.chatMessages.append(ChatMessage.user(message))
        session.chatMessages.append(ChatMessage.assistant(response))

        return response
    }

    // MARK: - Context Preparation

    private func prepareTranscriptContext(for session: LiveSession) -> String {
        let redactedTranscript = session.redactedTranscript

        // Estimate tokens
        let wordCount = redactedTranscript.split(separator: " ").count
        let estimatedTokens = Int(Double(wordCount) * tokensPerWord)

        if estimatedTokens <= maxContextTokens {
            // Full transcript fits
            return redactedTranscript
        }

        // Truncate to most recent content
        let segments = session.transcriptSegments
            .sorted { $0.startTime > $1.startTime } // Most recent first

        var truncatedSegments: [TranscriptSegment] = []
        var currentTokens = 0

        for segment in segments {
            let segmentWords = segment.text.split(separator: " ").count
            let segmentTokens = Int(Double(segmentWords) * tokensPerWord)

            if currentTokens + segmentTokens > maxContextTokens {
                break
            }

            truncatedSegments.append(segment)
            currentTokens += segmentTokens
        }

        // Reverse to chronological order
        truncatedSegments.reverse()

        // Build truncated transcript
        let truncatedText = truncatedSegments
            .map { "[\($0.speaker.label)] \($0.text)" }
            .joined(separator: "\n\n")

        return "[Earlier content truncated for length]\n\n" + truncatedText
    }
}
```

### 4.6 SessionStorageService

Handles persistence and recovery.

```swift
/// Manages session persistence to disk
/// File: ClinicalAnon/Services/Session/SessionStorageService.swift

import Foundation

class SessionStorageService {

    // MARK: - Configuration

    private static let sessionsDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Redactor")
            .appendingPathComponent("Sessions")
    }()

    // MARK: - Directory Management

    static func sessionDirectory(for session: LiveSession) -> URL {
        sessionsDirectory.appendingPathComponent(session.id.uuidString)
    }

    static func sessionDirectory(forId id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent(id.uuidString)
    }

    func createSessionDirectory(for session: LiveSession) throws {
        let dir = Self.sessionDirectory(for: session)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("audio"),
            withIntermediateDirectories: true
        )
    }

    // MARK: - Save/Load

    func saveSession(_ session: LiveSession) async throws {
        let dir = Self.sessionDirectory(for: session)

        // Save metadata
        let metadataURL = dir.appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(session)
        try data.write(to: metadataURL)
    }

    func loadSession(id: UUID) async throws -> LiveSession {
        let dir = Self.sessionDirectory(forId: id)
        let metadataURL = dir.appendingPathComponent("metadata.json")

        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(LiveSession.self, from: data)
    }

    func loadAllSessions() async throws -> [LiveSession] {
        guard FileManager.default.fileExists(atPath: Self.sessionsDirectory.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: Self.sessionsDirectory,
            includingPropertiesForKeys: nil
        )

        var sessions: [LiveSession] = []

        for dir in contents {
            guard dir.hasDirectoryPath else { continue }

            if let id = UUID(uuidString: dir.lastPathComponent) {
                do {
                    let session = try await loadSession(id: id)
                    sessions.append(session)
                } catch {
                    print("Failed to load session \(id): \(error)")
                }
            }
        }

        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Deletion

    func deleteSession(_ session: LiveSession) async {
        let dir = Self.sessionDirectory(for: session)
        try? FileManager.default.removeItem(at: dir)
    }

    func deleteAllSessions() async {
        try? FileManager.default.removeItem(at: Self.sessionsDirectory)
    }

    // MARK: - Orphan Cleanup

    /// Find sessions older than 24 hours that have been handed off
    func findSessionsReadyForCleanup() async throws -> [LiveSession] {
        let allSessions = try await loadAllSessions()
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

        return allSessions.filter { session in
            session.state == .handedOff && session.createdAt < cutoff
        }
    }
}
```

---

## 5. Views & UI

### 5.1 View Hierarchy

```
MainContentView
├── SessionSidebarView           // Session list
│   ├── SessionRowView           // Individual session row
│   └── NewSessionButton
├── SessionDetailView            // Selected session content
│   ├── TranscriptView           // Scrolling transcript
│   │   ├── TranscriptSegmentView
│   │   └── TranscriptionGapView
│   ├── SessionChatView          // AI chat interface
│   │   ├── ChatMessageView
│   │   └── ChatInputView
│   └── SessionControlBar        // Record/pause/stop controls
└── ExistingWorkflow             // Redact/Improve/Restore phases
```

### 5.2 SessionSidebarView

```swift
/// Sidebar showing all sessions for the day
/// File: ClinicalAnon/Views/Session/SessionSidebarView.swift

import SwiftUI

struct SessionSidebarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedSession: LiveSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Today's Sessions")
                    .font(.headline)
                Spacer()
                Button(action: startNewSession) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Start new recording")
            }
            .padding()

            Divider()

            // Session list
            List(selection: $selectedSession) {
                ForEach(sessionManager.sessions) { session in
                    SessionRowView(session: session)
                        .tag(session)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(width: 250)
    }

    private func startNewSession() {
        Task {
            do {
                let session = try await sessionManager.startSession()
                selectedSession = session
            } catch {
                // Show error
            }
        }
    }
}

struct SessionRowView: View {
    @ObservedObject var session: LiveSession

    var body: some View {
        HStack {
            // State indicator
            stateIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .fontWeight(.medium)
                Text(session.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // State label
            Text(stateLabel)
                .font(.caption)
                .foregroundColor(stateColor)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        case .paused:
            Image(systemName: "pause.fill")
                .foregroundColor(.orange)
                .font(.caption2)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .handedOff:
            Image(systemName: "arrow.right.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .complete: return "Complete"
        case .handedOff: return "In Redact"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .recording: return .red
        case .paused: return .orange
        case .complete: return .green
        case .handedOff: return .blue
        }
    }
}
```

### 5.3 SessionDetailView

```swift
/// Main content area for a selected session
/// File: ClinicalAnon/Views/Session/SessionDetailView.swift

import SwiftUI

struct SessionDetailView: View {
    @ObservedObject var session: LiveSession
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var aiService: SessionAIService

    @State private var showingChat = true
    @State private var chatMessage = ""

    init(session: LiveSession, bedrockService: BedrockService) {
        self.session = session
        self._aiService = StateObject(wrappedValue: SessionAIService(bedrockService: bedrockService))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Control bar
            SessionControlBar(session: session)

            Divider()

            // Main content: transcript + chat
            HSplitView {
                // Transcript
                TranscriptView(session: session)
                    .frame(minWidth: 400)

                // Chat (collapsible)
                if showingChat {
                    SessionChatView(
                        session: session,
                        aiService: aiService,
                        message: $chatMessage
                    )
                    .frame(minWidth: 300, maxWidth: 400)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showingChat) {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .help("Toggle AI Chat")
            }

            ToolbarItem {
                Toggle(isOn: $aiService.includeTranscriptContext) {
                    Image(systemName: "doc.text")
                }
                .help("Include transcript in AI context")
            }
        }
    }
}

struct SessionControlBar: View {
    @ObservedObject var session: LiveSession
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        HStack {
            // Session name (editable when complete)
            if session.state == .complete {
                TextField("Session name", text: $session.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
            } else {
                Text(session.displayName)
                    .font(.headline)
            }

            Spacer()

            // Recording indicator
            if session.state == .recording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(session.formattedDuration)
                        .monospacedDigit()
                }
            }

            // Controls
            HStack(spacing: 12) {
                switch session.state {
                case .recording:
                    Button("Pause") {
                        sessionManager.pauseSession(session)
                    }
                    Button("Stop") {
                        Task {
                            await sessionManager.stopSession(session)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                case .paused:
                    Button("Resume") {
                        Task {
                            try? await sessionManager.resumeSession(session)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Stop") {
                        Task {
                            await sessionManager.stopSession(session)
                        }
                    }

                case .complete:
                    Button("Create Notes") {
                        handoffToRedact()
                    }
                    .buttonStyle(.borderedProminent)

                    Menu {
                        Button("Export Transcript...") { }
                        Button("Export Audio...") { }
                        Divider()
                        Button("Delete Session", role: .destructive) {
                            Task {
                                await sessionManager.deleteSession(session)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                case .handedOff:
                    Text("Processing in Redact phase")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private func handoffToRedact() {
        let transcript = sessionManager.handoffToRedact(session)
        // Navigate to Redact phase with transcript
        // (Implementation via WorkflowViewModel binding)
    }
}
```

### 5.4 TranscriptView

```swift
/// Displays the scrolling transcript with speaker labels
/// File: ClinicalAnon/Views/Session/TranscriptView.swift

import SwiftUI

struct TranscriptView: View {
    @ObservedObject var session: LiveSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedSegments) { segment in
                        TranscriptSegmentView(
                            segment: segment,
                            entities: entitiesInSegment(segment)
                        )
                        .id(segment.id)
                    }

                    // Auto-scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onChange(of: session.transcriptSegments.count) { _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var sortedSegments: [TranscriptSegment] {
        session.transcriptSegments.sorted { $0.startTime < $1.startTime }
    }

    private func entitiesInSegment(_ segment: TranscriptSegment) -> [Entity] {
        session.detectedEntities.filter { entity in
            segment.text.localizedCaseInsensitiveContains(entity.originalText)
        }
    }
}

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let entities: [Entity]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(segment.formattedStartTime)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Speaker label
            Text(segment.speaker.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(speakerColor)
                .frame(width: 70, alignment: .leading)

            // Text with entity highlighting
            HighlightedSegmentText(
                text: segment.text,
                entities: entities
            )
        }
    }

    private var speakerColor: Color {
        switch segment.speaker {
        case .clinician: return .blue
        case .other: return .purple
        }
    }
}

struct HighlightedSegmentText: View {
    let text: String
    let entities: [Entity]

    var body: some View {
        // Use existing HighlightedTextView pattern or simplified version
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString(text)

        for entity in entities {
            if let range = result.range(of: entity.originalText, options: .caseInsensitive) {
                result[range].backgroundColor = entity.type.highlightColor.opacity(0.3)
            }
        }

        return result
    }
}
```

### 5.5 SessionChatView

```swift
/// AI chat interface for the session
/// File: ClinicalAnon/Views/Session/SessionChatView.swift

import SwiftUI

struct SessionChatView: View {
    @ObservedObject var session: LiveSession
    @ObservedObject var aiService: SessionAIService
    @Binding var message: String

    @EnvironmentObject var credentialsManager: AWSCredentialsManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session AI")
                    .font(.headline)
                Spacer()
                if let lastUpdate = session.lastTranscriptUpdate {
                    Text("Context: \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(session.chatMessages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }

                        if aiService.isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: session.chatMessages.count) { _ in
                    if let last = session.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack {
                TextField("Ask about the session...", text: $message)
                    .textFieldStyle(.plain)
                    .onSubmit(sendMessage)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(message.isEmpty || aiService.isProcessing)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sendMessage() {
        guard !message.isEmpty else { return }

        let text = message
        message = ""

        Task {
            do {
                _ = try await aiService.sendMessage(
                    text,
                    session: session,
                    model: credentialsManager.selectedModel
                )
            } catch {
                // Show error
            }
        }
    }
}
```

### 5.6 SessionStartConfirmView

Consent reminder shown before starting a recording.

```swift
/// Confirmation dialog with consent reminder before starting recording
/// File: ClinicalAnon/Views/Session/SessionStartConfirmView.swift

import SwiftUI

struct SessionStartConfirmView: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 40))
                .foregroundColor(.red)

            Text("Start Recording")
                .font(.headline)

            Text("Before recording, ensure you have obtained consent from all participants to record this session.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("I Have Consent – Start Recording") {
                    isPresented = false
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
```

### 5.7 SessionNamePromptView

Explicit naming prompt shown when a session stops.

```swift
/// Prompt to name a session after recording stops
/// File: ClinicalAnon/Views/Session/SessionNamePromptView.swift

import SwiftUI

struct SessionNamePromptView: View {
    @ObservedObject var session: LiveSession
    @Binding var isPresented: Bool

    @State private var sessionName: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Recording Complete")
                .font(.headline)

            Text("Duration: \(session.formattedDuration)")
                .foregroundColor(.secondary)

            TextField("Session name (optional)", text: $sessionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Text("Leave blank to use timestamp: \(session.formattedTimestamp)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Skip") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Save Name") {
                    session.name = sessionName
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            sessionName = session.name
        }
    }
}
```

### 5.8 WhisperModelDownloadView

Model download progress and management UI.

```swift
/// UI for downloading and managing Whisper models
/// File: ClinicalAnon/Views/Session/WhisperModelDownloadView.swift

import SwiftUI

struct WhisperModelDownloadView: View {
    @ObservedObject var transcriptionService: TranscriptionService
    @State private var downloadProgress: Double = 0
    @State private var isDownloading: Bool = false
    @State private var downloadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Whisper Models")
                .font(.headline)

            ForEach(TranscriptionService.WhisperModel.allCases, id: \.self) { model in
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.displayName)
                            .fontWeight(.medium)
                        Text("\(model.approximateSize) • RAM: \(model.approximateRAM)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if model == transcriptionService.currentModel {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if isModelDownloaded(model) {
                        Button("Activate") {
                            activateModel(model)
                        }
                        .buttonStyle(.bordered)
                    } else if model == .small {
                        Text("Bundled")
                            .foregroundColor(.secondary)
                    } else {
                        Button("Download") {
                            downloadModel(model)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloading)
                    }
                }
                .padding(.vertical, 8)

                if isDownloading && model != .small {
                    ProgressView(value: downloadProgress)
                }
            }

            if let error = downloadError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // RAM warning for large models
            if ProcessInfo.processInfo.physicalMemory < 16 * 1024 * 1024 * 1024 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Your Mac has less than 16GB RAM. Large models may cause performance issues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }

    private func isModelDownloaded(_ model: TranscriptionService.WhisperModel) -> Bool {
        // Check if model exists in Application Support/Models/whisper/
        // Implementation via WhisperModelManager
        return false
    }

    private func downloadModel(_ model: TranscriptionService.WhisperModel) {
        isDownloading = true
        downloadError = nil

        Task {
            do {
                // Use WhisperKit's built-in download API
                // Progress updates via callback
                try await transcriptionService.loadModel(model)
                isDownloading = false
            } catch {
                downloadError = "Download failed: \(error.localizedDescription)"
                isDownloading = false
            }
        }
    }

    private func activateModel(_ model: TranscriptionService.WhisperModel) {
        Task {
            try? await transcriptionService.loadModel(model)
        }
    }
}
```

---

## 6. Storage & Persistence

### 6.1 Directory Structure

```
~/Library/Application Support/Redactor/
├── Sessions/
│   ├── {uuid}/
│   │   ├── metadata.json          # Session state, transcript, entities
│   │   └── audio/
│   │       ├── mic_000.m4a
│   │       ├── mic_001.m4a
│   │       ├── sys_000.m4a
│   │       ├── sys_001.m4a
│   │       └── ...
│   └── {uuid}/
│       └── ...
├── Models/
│   └── whisper/
│       ├── small/                  # Bundled
│       ├── medium/                 # Downloaded
│       └── large-v3/               # Downloaded
└── Exports/
    └── (temporary export staging)
```

### 6.2 Metadata Schema

```json
{
  "id": "uuid",
  "createdAt": "2026-02-01T10:30:00Z",
  "state": "complete",
  "name": "Client session",
  "recordingDuration": 3120.5,
  "transcriptSegments": [
    {
      "id": "uuid",
      "speaker": "clinician",
      "text": "How have you been feeling this week?",
      "startTime": 0.0,
      "endTime": 3.2,
      "chunkIndex": 0,
      "confidence": 0.92
    }
  ],
  "detectedEntities": [
    {
      "id": "uuid",
      "originalText": "Jane Smith",
      "replacementCode": "[CLIENT_A]",
      "type": "personClient",
      "positions": [[45, 55]],
      "confidence": 0.95
    }
  ],
  "audioChunkPaths": [
    {
      "id": "uuid",
      "stream": "microphone",
      "chunkIndex": 0,
      "startTime": 0,
      "endTime": 180,
      "filePath": "audio/mic_000.m4a",
      "fileSize": 1234567,
      "isProcessed": true
    }
  ]
}
```

### 6.3 Auto-Save Strategy

| Trigger | What's Saved |
|---------|-------------|
| New transcript segment | Full metadata.json |
| Entity detected | Full metadata.json |
| State change | Full metadata.json |
| Audio chunk complete | Chunk file + metadata.json |
| Every 30 seconds | Full metadata.json (if changes) |

---

## 7. Audio Pipeline

### 7.1 Capture Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ AVAudioEngine│────▶│ Audio Buffer │────▶│ AVAssetWriter│────▶ mic_XXX.m4a
│ (Microphone) │     │ (16kHz mono) │     │ (AAC 128kbps)│
└──────────────┘     └──────────────┘     └──────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ScreenCapture │────▶│ Audio Buffer │────▶│ AVAssetWriter│────▶ sys_XXX.m4a
│ Kit (System) │     │ (16kHz mono) │     │ (AAC 128kbps)│
└──────────────┘     └──────────────┘     └──────────────┘
```

### 7.2 Chunk Rotation

```
Time:  0:00    3:00    6:00    9:00
       |-------|-------|-------|
Chunk:    0       1       2      ...

Overlap: Each chunk includes 30s from previous chunk end
         for transcription continuity
```

### 7.3 Audio Specifications

| Property | Value |
|----------|-------|
| Sample rate | 16,000 Hz (WhisperKit requirement) |
| Channels | 1 (mono) |
| Format | M4A container, AAC codec |
| Bitrate | 128 kbps |
| Chunk duration | 3 minutes |
| Overlap | 30 seconds |

---

## 8. Transcription Pipeline

### 8.1 Processing Flow

```
Audio Chunk Ready
       │
       ▼
┌──────────────────┐
│ Load audio file  │
│ (16kHz mono PCM) │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  WhisperKit      │
│  transcribe()    │
│  - language: en  │
│  - task: transcribe
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Parse segments   │
│ - Add timestamps │
│ - Add speaker    │
│ - Add chunk ref  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Deduplicate      │
│ overlap region   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Emit segments    │
│ via callback     │
└──────────────────┘
```

### 8.2 Overlap Deduplication

When processing chunk N:
1. Get last 30 seconds of text from chunk N-1
2. Find matching text at start of chunk N
3. Discard duplicate segments from chunk N

---

## 9. Live Redaction Pipeline

### 9.1 Incremental Detection

```
New Transcript Segment
         │
         ▼
┌────────────────────┐
│ AnonymizationEngine│
│ .anonymize()       │
│ - Pass existing    │
│   EntityMapping    │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│ Merge new entities │
│ into session       │
│ - Avoid duplicates │
│ - Update positions │
└─────────┬──────────┘
          │
          ▼
┌────────────────────┐
│ Notify UI of       │
│ entity changes     │
└────────────────────┘
```

### 9.2 Final Pass

On session stop:
1. Concatenate all segments into full transcript
2. Run full entity detection
3. Replace incremental entities with final set
4. Ensure position indices are correct for full text

---

## 10. Session AI Integration

### 10.1 Context Building

```
User Message
     │
     ▼
┌─────────────────────────┐
│ Build system prompt     │
│ - Base clinical prompt  │
│ - Privacy guidelines    │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ If includeContext:      │
│ - Get redactedTranscript│
│ - Truncate if >10k tokens
│ - Append to system prompt
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ ConversationContext     │
│ - Add summary if needed │
│ - Get recent messages   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ BedrockService.invoke() │
│ - System prompt         │
│ - Message history       │
│ - Model selection       │
└─────────────────────────┘
```

### 10.2 Token Management

| Scenario | Approach |
|----------|----------|
| Transcript < 10k tokens | Include full transcript |
| Transcript > 10k tokens | Truncate to most recent content |
| 50+ messages in chat | ConversationContext summarizes older messages |

---

## 11. Handoff to Redact Phase

### 11.1 Handoff Data

```swift
struct SessionHandoff {
    let rawTranscript: String      // Full unredacted transcript
    let sessionName: String        // For document naming
    let duration: TimeInterval     // For reference
    let segmentCount: Int          // For reference
}
```

### 11.2 Handoff Flow

1. User clicks "Create Notes" on complete session
2. SessionManager.handoffToRedact() called
3. Session state changes to `.handedOff`
4. Session remains visible in sidebar (greyed out, "In Redact" state)
5. Raw transcript passed to WorkflowViewModel
6. WorkflowViewModel enters Redact phase
7. Full entity detection runs (fresh, not using session's EntityMapping)
8. User reviews and adjusts as normal
9. On notes completion, deletion prompt fires
10. Session removed from sidebar only after deletion confirmed

**Why session stays visible:** If the app crashes during the Redact phase, the session data still exists on disk. Keeping it visible ensures the deletion prompt fires on next app launch, even if the handoff was interrupted.

### 11.3 Why Fresh Detection?

- Incremental detection may miss context-dependent entities
- User expects full review capability in Redact phase
- Consistent with existing workflow UX
- EntityMapping from live session is discarded

**Note on EntityMapping:** The live session's EntityMapping (used for AI chat context) is intentionally discarded on handoff. While the user may have seen `[PERSON_A]` during the session, the Redact phase runs fresh detection which may assign different codes. This is acceptable because:

1. The Redact phase is a complete review opportunity
2. AI chat history doesn't persist to Redact phase
3. Fresh detection with full context is more accurate
4. Users are already familiar with this workflow pattern

For MVP, this approach is simpler and consistent with existing UX. Future enhancement could optionally seed the Redact phase with the session's EntityMapping if user feedback indicates a need.

---

## 12. Export Functionality

### 12.1 Export Formats

| Format | Content | Notes | Phase |
|--------|---------|-------|-------|
| Transcript (redacted) | `.txt`, `.md` | Entities replaced with codes | Phase 4 |
| Transcript (unredacted) | `.txt`, `.md` | Original text, PII warning | Phase 4 |
| Audio (mic) | `.m4a` | Clinician's microphone | Phase 4 |
| Audio (system) | `.m4a` | Remote participants | Phase 4 |
| Audio (combined) | `.m4a` | Both streams merged (requires mixing) | Phase 4 (deferred) |

**Note on Combined Audio Export:** Merging two audio streams requires:
- Loading both audio files via AVAssetReader
- Creating an AVMutableComposition
- Mixing/interleaving samples
- Writing combined output via AVAssetWriter

This is non-trivial and is deferred to Phase 4. Initial export will offer separate mic/system files only.

### 12.2 Export Flow

```swift
func exportTranscript(
    session: LiveSession,
    format: ExportFormat,
    redacted: Bool
) async throws -> URL {
    let text = redacted ? session.redactedTranscript : session.rawTranscript

    // Show warning for unredacted export
    if !redacted {
        let confirmed = await showPIIWarning()
        guard confirmed else { throw ExportError.cancelled }
    }

    // Create temp file
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(session.displayName).\(format.extension)")

    try text.write(to: tempURL, atomically: true, encoding: .utf8)

    // Show save panel
    let panel = NSSavePanel()
    panel.nameFieldStringValue = tempURL.lastPathComponent

    guard panel.runModal() == .OK, let url = panel.url else {
        throw ExportError.cancelled
    }

    try FileManager.default.copyItem(at: tempURL, to: url)
    return url
}
```

---

## 13. Deletion Flow

### 13.1 Deletion Triggers

| Trigger | Behavior |
|---------|----------|
| Notes workflow completes | Prompt immediately |
| User clicks "Delete Session" | Confirm and delete |
| App launch with old sessions | Show cleanup prompt |
| 24-hour timer expires | Auto-prompt on next app open |

### 13.2 Deletion Prompt (After Notes Complete)

```
┌─────────────────────────────────────────────────┐
│ Notes saved successfully                        │
│                                                 │
│ Delete the original recording and transcript   │
│ for this session?                              │
│                                                 │
│ Session: Client A – Mon 10:30am (52 min)       │
│                                                 │
│ ⚠ This cannot be undone.                       │
│                                                 │
│    [Delete Now]  [Export First]  [Keep for Later]
└─────────────────────────────────────────────────┘
```

### 13.3 Cleanup Prompt (App Launch)

Shown when sessions >24 hours old exist:

```
┌─────────────────────────────────────────────────┐
│ Sessions ready for cleanup                      │
│                                                 │
│ HANDED OFF                                      │
│ ☑ Client A – Mon 10:30am  ✓ Notes created      │
│ ☑ Client B – Mon 2:15pm   ✓ Notes created      │
│                                                 │
│ NOT HANDED OFF                                  │
│ ☐ Client C – Mon 4:00pm   ⚠ No notes created   │
│                                                 │
│        [Delete Selected]    [Keep All for Now] │
└─────────────────────────────────────────────────┘
```

---

## 14. Error Handling

### 14.1 Error Categories

| Category | Examples | Recovery |
|----------|----------|----------|
| Permission | Mic denied, Screen Recording denied | Guide to System Settings |
| Audio | Capture failed, Writer failed | Retry, alert user |
| Transcription | Model not loaded, Chunk failed | Retry with same/larger model |
| Storage | Disk full, Write failed | Alert, pause recording |
| AI | Bedrock timeout, Rate limited | Retry with backoff |

### 14.2 Transcription Failure Recovery

```swift
enum TranscriptionRecovery {
    case retryWithSameModel
    case retryWithLargerModel
    case markAsGap
    case skipChunk
}

func handleTranscriptionFailure(
    chunk: AudioChunkReference,
    error: Error
) async -> TranscriptionRecovery {
    // First retry with same model
    if !chunk.hasRetried {
        return .retryWithSameModel
    }

    // Offer larger model if available and not already using it
    if canUpgradeModel {
        let upgrade = await promptUserForModelUpgrade()
        if upgrade {
            return .retryWithLargerModel
        }
    }

    // Mark as gap
    return .markAsGap
}
```

---

## 15. Permissions & Entitlements

### 15.1 Required Permissions

| Permission | Usage | Prompt Timing |
|------------|-------|---------------|
| Microphone | Clinician audio capture | First session start |
| Screen Recording | System audio capture | First session start |

### 15.2 Entitlements

```xml
<!-- Entitlements.plist additions -->

<key>com.apple.security.device.audio-input</key>
<true/>

<!-- Note: Screen Recording does not have a specific entitlement -->
<!-- ScreenCaptureKit prompts automatically -->
```

### 15.3 Info.plist Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Redactor needs microphone access to record your voice during clinical sessions.</string>
```

---

## 16. File Structure

### 16.1 New Files

```
ClinicalAnon/
├── Models/
│   ├── LiveSession.swift
│   ├── TranscriptSegment.swift
│   ├── AudioChunkReference.swift
│   └── TranscriptionGap.swift
├── Services/
│   └── Session/
│       ├── SessionManager.swift
│       ├── AudioCaptureService.swift
│       ├── TranscriptionService.swift
│       ├── LiveRedactor.swift
│       ├── SessionAIService.swift
│       ├── SessionStorageService.swift
│       └── WhisperModelManager.swift          # Model download/management
└── Views/
    └── Session/
        ├── SessionSidebarView.swift
        ├── SessionDetailView.swift
        ├── SessionControlBar.swift
        ├── TranscriptView.swift
        ├── TranscriptSegmentView.swift
        ├── SessionChatView.swift
        ├── SessionExportView.swift
        ├── SessionCleanupView.swift
        ├── SessionNamePromptView.swift        # Explicit naming prompt on stop
        ├── SessionStartConfirmView.swift      # Consent reminder before recording
        └── WhisperModelDownloadView.swift     # Model download progress/management
```

### 16.2 Modified Files

| File | Changes |
|------|---------|
| `ClinicalAnonApp.swift` | Add SessionManager, handle recovery |
| `MainContentView.swift` | Add session mode toggle, sidebar |
| `WorkflowViewModel.swift` | Add handoff receiver |
| `DesignSystem.swift` | Add session-related colors/styles |
| `AppError.swift` | Add session error cases |

---

## 17. Implementation Phases

### Phase 1: Core Recording & Transcription (Weeks 1-2)

**Deliverables:**
- [ ] `LiveSession` model
- [ ] `TranscriptSegment` model
- [ ] `AudioCaptureService` (two-stream capture with shared start timestamp)
- [ ] `TranscriptionService` (WhisperKit integration)
- [ ] `SessionStorageService` (save/load)
- [ ] `SessionManager` (basic lifecycle)
- [ ] Basic UI (sidebar, transcript view, controls)
- [ ] `SessionNamePromptView` (explicit naming on stop)
- [ ] Auto-save every chunk

**Acceptance Criteria:**
- Can start/stop recording
- Microphone and system audio captured separately with synchronized timestamps
- Transcription produces speaker-labelled text
- Session persists across app restart
- Session naming prompt appears on stop

### Phase 2: Live Redaction (Week 3)

**Deliverables:**
- [ ] `LiveRedactor` service
- [ ] Incremental entity detection
- [ ] Entity highlighting in transcript view
- [ ] Handoff to Redact phase (session stays visible until deletion)
- [ ] Integration with existing `EntityMapping`

**Acceptance Criteria:**
- Entities detected incrementally as transcript grows
- Entities highlighted in real-time
- Handoff produces clean input for Redact phase
- Fresh detection runs on handoff
- Handed-off sessions remain visible in sidebar with "In Redact" state

### Phase 3: Session AI Window (Week 4)

**Deliverables:**
- [ ] `SessionAIService`
- [ ] `SessionChatView`
- [ ] Context toggle (include/exclude transcript)
- [ ] Token-aware truncation
- [ ] Integration with existing `ConversationContext`

**Acceptance Criteria:**
- Chat interface works during recording
- Transcript context included when enabled
- Long transcripts truncated appropriately
- Conversation history maintained

### Phase 4: Polish & Reliability (Week 5)

**Deliverables:**
- [ ] Export functionality (transcript + separate audio files)
- [ ] Combined audio export (deferred if complex)
- [ ] Deletion prompts (after notes, on launch)
- [ ] `WhisperModelManager` service
- [ ] `WhisperModelDownloadView` with progress indicator
- [ ] RAM check before large model download
- [ ] Error recovery UI for failed chunks
- [ ] Session rename functionality
- [ ] Pause/resume with gap markers
- [ ] Comprehensive error handling
- [ ] Consent reminder dialog (`SessionStartConfirmView`)

**Acceptance Criteria:**
- All export formats work (combined audio optional)
- Deletion prompts appear at correct times
- Failed chunks show gap and retry option
- Pause inserts visible gap in transcript
- Model download shows progress and handles failures
- Consent reminder shown before first recording

---

## 18. Testing Strategy

### 18.1 Unit Tests

| Component | Tests |
|-----------|-------|
| `LiveSession` | State transitions, computed properties |
| `TranscriptSegment` | Formatting, ordering |
| `EntityMapping` | Reuse existing tests, add session-specific |
| `SessionStorageService` | Save/load round-trip, recovery |

### 18.2 Integration Tests

| Flow | Test |
|------|------|
| Recording lifecycle | Start → Record → Stop → Complete |
| Pause/Resume | Pause → Resume → Gap marker appears |
| Handoff | Complete → Handoff → Redact phase receives transcript |
| Crash recovery | Kill app → Relaunch → Sessions restored |

### 18.3 Manual Testing Checklist

- [ ] Two-stream capture without feedback loop
- [ ] 60-minute recording performance
- [ ] Transcription accuracy (clinical terms)
- [ ] Memory usage over long session
- [ ] UI responsiveness during transcription
- [ ] Export formats all valid
- [ ] Deletion removes all files

---

## Appendix A: Dependencies

### A.1 New Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| WhisperKit | Latest | On-device transcription |

### A.2 Framework Dependencies

| Framework | Purpose |
|-----------|---------|
| AVFoundation | Audio capture, file writing |
| ScreenCaptureKit | System audio capture |
| Combine | Reactive state management |

---

## Appendix B: Performance Targets

| Metric | Target |
|--------|--------|
| Transcription latency | < 30 seconds per 3-min chunk |
| Memory usage (recording) | < 500 MB |
| Memory usage (WhisperKit small) | < 1 GB |
| Memory usage (WhisperKit large) | < 4 GB |
| UI frame rate | 60 fps during recording |
| Auto-save frequency | Every chunk (3 min) |

---

## Appendix C: Security Considerations

| Concern | Mitigation |
|---------|------------|
| Audio stored on disk | Deleted after handoff + confirmation |
| Transcript stored on disk | Deleted with audio |
| FileVault dependency | Acceptable for MVP; document requirement |
| Memory contains PII | Cleared on app background/terminate |
| Network transmission | Only redacted text sent to Bedrock |

---

*End of Technical Specification*
