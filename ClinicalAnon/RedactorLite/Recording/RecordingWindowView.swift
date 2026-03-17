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

    // Timer to poll audio levels (SessionManager proxies are computed, not @Published)
    @State private var levelRefreshTimer: Timer?
    @State private var micLevel: Float = 0
    @State private var sysLevel: Float = 0

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
                    sessionManager: sessionManager,
                    transcriptionService: transcriptionService,
                    coworkExport: coworkExport,
                    onStartRecording: startRecording,
                    onStopRecording: stopRecording,
                    onPauseRecording: pauseRecording,
                    onResumeRecording: resumeRecording,
                    onTransferToRedactor: transferToRedactor
                )
                .frame(minWidth: 280, maxWidth: 320)
                .glassPanel()

                // Panel 2: Live Transcript
                LiveTranscriptPanel(
                    session: sessionManager.activeSession,
                    phase: phase
                )
                .frame(maxWidth: .infinity)
                .glassPanel()

                // Panel 3: Detected Entities
                SessionEntityPanel(
                    session: sessionManager.activeSession
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
                  let session = sessionManager.activeSession,
                  session.id == sessionId else { return }
            coworkExport.writeChunk(for: session)
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
                phase = .recording
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        guard let session = sessionManager.activeSession else { return }
        Task {
            await sessionManager.stopSession(session)
            coworkExport.finalizeSession()
            phase = .stopped
        }
    }

    private func pauseRecording() {
        guard let session = sessionManager.activeSession else { return }
        sessionManager.pauseSession(session)
    }

    private func resumeRecording() {
        guard let session = sessionManager.activeSession else { return }
        Task {
            try? await sessionManager.resumeSession(session)
        }
    }

    private func transferToRedactor() {
        guard let session = sessionManager.activeSession ?? sessionManager.sessions.first(where: { $0.state == .complete }) else {
            return
        }
        let transcript = sessionManager.handoffToRedact(session)
        NotificationCenter.default.post(name: .transferTranscript, object: transcript)
        RecordingWindowController.shared.closeRecordingWindow()
    }
}
