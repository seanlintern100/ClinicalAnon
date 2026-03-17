//
//  RecordingWindowView.swift
//  Redactor Lite
//
//  Purpose: Top-level 3-panel recording window — Setup | Transcript | Entities
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Recording Phase

enum RecordingPhase {
    case setup      // Pre-recording form
    case recording  // Active recording with live transcript
    case stopped    // Recording complete, review + transfer
}

// MARK: - Recording Window View

struct RecordingWindowView: View {

    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var coworkExport = CoworkExportService()

    @State private var phase: RecordingPhase = .setup
    @State private var metadata = SessionMetadata.fromLastUsed()
    @State private var showSettings = false
    @State private var showFirstTimeSetup = false
    @State private var errorMessage: String?
    @State private var multiSpeaker: Bool = false
    /// Retains session reference after stop so transcript/entities stay visible
    @State private var currentSession: LiveSession?

    // Timer to poll audio levels and duration (SessionManager level proxies are computed, not @Published,
    // and session.recordingDuration changes don't propagate through sessionManager's objectWillChange)
    @State private var levelRefreshTimer: Timer?
    @State private var micLevel: Float = 0
    @State private var sysLevel: Float = 0
    @State private var displayDuration: String = "0:00"

    /// Whether first-time setup (folder + model) is needed
    private var needsFirstTimeSetup: Bool {
        !coworkExport.hasRootFolder || !transcriptionService.isModelLoaded
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            GradientPageBackground()

            HStack(spacing: DesignSystem.Spacing.medium) {
                // Panel 1: Session Setup / Controls
                SessionSetupPanel(
                    phase: $phase,
                    metadata: $metadata,
                    errorMessage: $errorMessage,
                    showSettings: $showSettings,
                    multiSpeaker: $multiSpeaker,
                    micLevel: micLevel,
                    sysLevel: sysLevel,
                    displayDuration: displayDuration,
                    sessionManager: sessionManager,
                    transcriptionService: transcriptionService,
                    coworkExport: coworkExport,
                    onStartRecording: startRecording,
                    onStopRecording: stopRecording,
                    onPauseRecording: pauseRecording,
                    onResumeRecording: resumeRecording,
                    onTransferToRedactor: transferToRedactor,
                    onNewSession: newSession
                )
                .frame(minWidth: 280, maxWidth: 320)
                .glassPanel()

                // Panel 2: Live Transcript
                LiveTranscriptPanel(
                    session: currentSession,
                    phase: phase
                )
                .frame(maxWidth: .infinity)
                .glassPanel()

                // Panel 3: Detected Entities
                SessionEntityPanel(
                    session: currentSession
                )
                .frame(minWidth: 240, maxWidth: 280)
                .glassPanel()
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.bottom, DesignSystem.Spacing.medium)
            .padding(.top, DesignSystem.Spacing.small)
        }
        .onAppear {
            if needsFirstTimeSetup {
                showFirstTimeSetup = true
            }
        }
        .sheet(isPresented: $showFirstTimeSetup) {
            FirstTimeSetupView(
                coworkExport: coworkExport,
                transcriptionService: transcriptionService
            )
        }
        .sheet(isPresented: $showSettings) {
            RecordingSettingsView(coworkExport: coworkExport)
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionChunkRedacted)) { notification in
            guard let sessionId = notification.userInfo?["sessionId"] as? UUID,
                  let session = currentSession,
                  session.id == sessionId else { return }
            coworkExport.writeChunk(for: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoStartRecording)) { notification in
            guard phase == .setup,
                  let info = notification.userInfo as? [String: String] else { return }
            applyURLMetadata(info)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        guard !metadata.clientInitials.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter client initials"
            return
        }
        guard coworkExport.hasRootFolder else {
            errorMessage = "Please select an export folder"
            return
        }

        Task {
            do {
                // Start Cowork export
                try coworkExport.startSession(metadata: metadata)

                // Enable diarization if multi-speaker selected
                if multiSpeaker {
                    UserDefaults.standard.set(true, forKey: SettingsKeys.enhancedDiarizationEnabled)
                }

                // Start audio recording session
                let session = try await sessionManager.startSession()
                session.hasMultipleParticipants = multiSpeaker
                currentSession = session
                phase = .recording
                errorMessage = nil
                startLevelTimer()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        guard let session = currentSession else { return }
        Task {
            await sessionManager.stopSession(session)
            coworkExport.finalizeSession()
            stopLevelTimer()
            phase = .stopped
        }
    }

    private func pauseRecording() {
        guard let session = currentSession else { return }
        sessionManager.pauseSession(session)
    }

    private func resumeRecording() {
        guard let session = currentSession else { return }
        Task {
            try? await sessionManager.resumeSession(session)
        }
    }

    private func newSession() {
        currentSession = nil
        phase = .setup
        metadata = SessionMetadata.fromLastUsed()
        multiSpeaker = false
        displayDuration = "0:00"
    }

    private func transferToRedactor() {
        guard let session = currentSession ?? sessionManager.sessions.first(where: { $0.state == .complete }) else {
            return
        }
        stopLevelTimer()
        let transcript = sessionManager.handoffToRedact(session)
        NotificationCenter.default.post(name: .transferTranscript, object: transcript)
        RecordingWindowController.shared.closeRecordingWindow()
    }

    // MARK: - URL Scheme Auto-Start

    /// Populates metadata from URL scheme parameters and auto-starts recording
    private func applyURLMetadata(_ info: [String: String]) {
        if let initials = info["initials"], !initials.isEmpty {
            metadata.clientInitials = initials
        }
        if let type = info["type"], let sessionType = SessionType(rawValue: type) {
            metadata.sessionType = sessionType
        }
        if let otherDesc = info["otherType"] {
            metadata.otherTypeDescription = otherDesc
        }
        if let length = info["length"], let mins = Int(length) {
            metadata.sessionLengthMinutes = max(10, min(180, mins))
        }
        if let goals = info["goals"] {
            metadata.sessionGoals = goals
        }
        if let multi = info["multiSpeaker"] {
            multiSpeaker = (multi == "true" || multi == "1")
        }

        // Brief delay for UI to settle, then auto-start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            startRecording()
        }
    }

    // MARK: - Level & Duration Polling

    private func startLevelTimer() {
        levelRefreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                micLevel = sessionManager.microphoneLevel
                sysLevel = sessionManager.systemLevel
                if let session = currentSession {
                    displayDuration = session.formattedDuration
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelRefreshTimer = timer
    }

    private func stopLevelTimer() {
        levelRefreshTimer?.invalidate()
        levelRefreshTimer = nil
    }
}
