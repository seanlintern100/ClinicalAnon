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

enum RecordingTab {
    case transcript
    case dashboard
    case notes
}

// MARK: - Recording Window View

struct RecordingWindowView: View {

    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var transcriptionService = TranscriptionService.shared
    @StateObject private var exportService = SessionExportService()

    @State private var phase: RecordingPhase = .setup
    @State private var activeTab: RecordingTab = .transcript
    @State private var metadata = SessionMetadata.fromLastUsed()
    @State private var showSettings = false
    @State private var showFirstTimeSetup = false
    @State private var errorMessage: String?
    @State private var multiSpeaker: Bool = false
    /// Retains session reference after stop so transcript/entities stay visible
    @State private var currentSession: LiveSession?
    @State private var notesAvailable = false

    // Timer to poll audio levels and duration (SessionManager level proxies are computed, not @Published,
    // and session.recordingDuration changes don't propagate through sessionManager's objectWillChange)
    @State private var levelRefreshTimer: Timer?
    @State private var micLevel: Float = 0
    @State private var sysLevel: Float = 0
    @State private var displayDuration: String = "0:00"

    /// Whether first-time setup (model download) is needed
    private var needsFirstTimeSetup: Bool {
        !transcriptionService.isModelCached(size: transcriptionService.selectedModelSize)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            GradientPageBackground()

            VStack(spacing: 0) {
                // Content — transcript only (redaction-only build)
                transcriptContent
            }
        }
        .onAppear {
            if needsFirstTimeSetup {
                showFirstTimeSetup = true
            }
            // Check if clinical notes already exist (e.g. window reopened after notes were written)
            if let folder = exportService.sessionFolderURL,
               FileManager.default.fileExists(atPath: folder.appendingPathComponent("clinical_notes.json").path) {
                notesAvailable = true
            }
        }
        .sheet(isPresented: $showFirstTimeSetup) {
            FirstTimeSetupView(
                exportService: exportService,
                transcriptionService: transcriptionService
            )
        }
        .sheet(isPresented: $showSettings) {
            RecordingSettingsView(exportService: exportService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionChunkRedacted)) { notification in
            guard let sessionId = notification.userInfo?["sessionId"] as? UUID,
                  let session = currentSession,
                  session.id == sessionId else { return }
            exportService.writeChunk(for: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoStartRecording)) { notification in
            guard phase == .setup,
                  let info = notification.userInfo as? [String: String] else { return }
            applyURLMetadata(info)
        }
        // MCP notifications disabled — redaction-only build
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton("Transcript", tab: .transcript, icon: "text.quote")
            tabButton("Dashboard", tab: .dashboard, icon: "gauge")
            if notesAvailable {
                tabButton("Notes", tab: .notes, icon: "doc.text")
            }
            Spacer()
        }
    }

    private func tabButton(_ title: String, tab: RecordingTab, icon: String) -> some View {
        Button {
            activeTab = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(activeTab == tab ? Color.white.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .foregroundColor(activeTab == tab ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Transcript Content (3-panel layout)

    private var transcriptContent: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
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
                exportService: exportService,
                onStartRecording: startRecording,
                onStopRecording: stopRecording,
                onPauseRecording: pauseRecording,
                onResumeRecording: resumeRecording,
                onTransferToRedactor: transferToRedactor,
                onNewSession: newSession
            )
            .frame(minWidth: 280, maxWidth: 320)
            .glassPanel()

            LiveTranscriptPanel(
                session: currentSession,
                phase: phase
            )
            .frame(maxWidth: .infinity)
            .glassPanel()

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

    // MARK: - Dashboard Content (Copilot)

    private var dashboardContent: some View {
        CopilotDashboardView(
            sessionFolder: exportService.sessionFolderURL,
            privateFolderURL: exportService.privateFolderURL
        )
        .id("copilot-dashboard")  // Stable identity — prevents SwiftUI from recreating the view
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.bottom, DesignSystem.Spacing.medium)
        .padding(.top, DesignSystem.Spacing.small)
    }

    // MARK: - Notes Content

    private var notesContent: some View {
        ClinicalNotesView(
            sessionFolder: exportService.sessionFolderURL,
            privateFolderURL: exportService.privateFolderURL
        )
        .id("clinical-notes")
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.bottom, DesignSystem.Spacing.medium)
        .padding(.top, DesignSystem.Spacing.small)
    }

    // MARK: - Actions

    private func startRecording() {
        guard !metadata.clientInitials.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter client initials"
            return
        }
        guard exportService.hasRootFolder else {
            errorMessage = "Please select an export folder"
            return
        }

        Task {
            do {
                // Start session export
                try exportService.startSession(metadata: metadata)

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

                // HTTP server disabled — redaction-only build
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        guard let session = currentSession else { return }
        Task {
            await sessionManager.stopSession(session)
            exportService.finalizeSession()
            stopLevelTimer()
            phase = .stopped

            // Keep session active so Cowork can write clinical notes after session ends.
            // Session deactivates when user starts a new session or closes the window.
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
        notesAvailable = false
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
