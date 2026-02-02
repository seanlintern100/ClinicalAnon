//
//  SessionDetailView.swift
//  ClinicalAnon
//
//  Purpose: Detail view for a session with controls and transcript
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Detail View

/// Detail view showing session controls and transcript
struct SessionDetailView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @ObservedObject var sessionManager: SessionManager
    @StateObject private var aiService: SessionAIService

    @State private var showTranscriptExport = false
    @State private var showAudioExport = false
    @State private var showChatPanel = false

    // MARK: - Initialization

    init(session: LiveSession, sessionManager: SessionManager) {
        self._session = ObservedObject(wrappedValue: session)
        self._sessionManager = ObservedObject(wrappedValue: sessionManager)
        self._aiService = StateObject(wrappedValue: SessionAIService(
            bedrockService: BedrockService(),
            credentialsManager: .shared
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Control bar
            controlBar

            Divider()

            // Main content area: Transcript + Chat
            HStack(spacing: 0) {
                // Transcript view (left pane)
                TranscriptView(session: session)
                    .frame(maxWidth: .infinity)

                // Chat panel (right pane, collapsible)
                if showChatPanel {
                    Divider()

                    SessionChatView(session: session, aiService: aiService)
                        .frame(width: 350)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .sheet(isPresented: $showTranscriptExport) {
            TranscriptExportView(session: session)
        }
        .sheet(isPresented: $showAudioExport) {
            AudioExportView(session: session)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                HStack(spacing: DesignSystem.Spacing.small) {
                    Text(session.state.displayName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(stateColor)

                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text(session.formattedDuration)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    // Entity count indicator
                    if !session.detectedEntities.isEmpty {
                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                        Text("\(session.detectedEntities.count) entities")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.primaryTeal)
                    }
                }
            }

            Spacer()

            // Entity detection indicator
            if LiveRedactor.shared.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Detecting...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            // Audio level meters
            if session.state == .recording {
                audioLevelMeters
            }

            // Chat controls
            chatControls

            // Control buttons
            controlButtons
        }
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - State Color

    private var stateColor: Color {
        switch session.state {
        case .recording: return .red
        case .paused: return .orange
        case .complete: return .green
        case .handedOff: return DesignSystem.Colors.textSecondary
        }
    }

    // MARK: - Audio Level Meters

    private var audioLevelMeters: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            // Microphone selector + level
            VStack(spacing: 2) {
                Menu {
                    Button {
                        sessionManager.selectInputDevice(nil)
                    } label: {
                        HStack {
                            Text("System Default")
                            if sessionManager.selectedInputDevice == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    if !sessionManager.availableInputDevices.isEmpty {
                        Divider()

                        ForEach(sessionManager.availableInputDevices) { device in
                            Button {
                                sessionManager.selectInputDevice(device)
                            } label: {
                                HStack {
                                    Text(device.name)
                                    if sessionManager.selectedInputDevice?.id == device.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "mic.fill")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .onAppear {
                    sessionManager.refreshInputDevices()
                }

                AudioLevelMeter(level: sessionManager.microphoneLevel)
            }

            // System audio level
            VStack(spacing: 2) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                AudioLevelMeter(level: sessionManager.systemLevel)
            }
        }
    }

    // MARK: - Chat Controls

    private var chatControls: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            // Transcript context toggle
            Button {
                withAnimation {
                    aiService.includeTranscriptContext.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: aiService.includeTranscriptContext ? "doc.text.fill" : "doc.text")
                        .font(.caption)
                }
                .foregroundStyle(aiService.includeTranscriptContext
                    ? DesignSystem.Colors.primaryTeal
                    : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(aiService.includeTranscriptContext ? "Transcript included in AI context" : "Transcript excluded from AI context")

            // Chat panel toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChatPanel.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        .font(.caption)
                }
                .foregroundStyle(showChatPanel
                    ? DesignSystem.Colors.primaryTeal
                    : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(showChatPanel ? "Hide AI chat" : "Show AI chat")
        }
    }

    // MARK: - Control Buttons

    @ViewBuilder
    private var controlButtons: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            switch session.state {
            case .recording:
                // Pause button
                Button(action: pauseSession) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                // Stop button
                Button(action: stopSession) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

            case .paused:
                // Resume button
                Button(action: resumeSession) {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                // Stop button
                Button(action: stopSession) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

            case .complete:
                // Actions menu
                Menu {
                    Button(action: { showTranscriptExport = true }) {
                        Label("Export Transcript...", systemImage: "doc.text")
                    }

                    Button(action: { showAudioExport = true }) {
                        Label("Export Audio...", systemImage: "waveform")
                    }

                    Divider()

                    Button(action: sendToRedact) {
                        Label("Send to Redact", systemImage: "arrow.right.circle.fill")
                    }
                    .disabled(session.transcriptSegments.isEmpty)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)

                // Send to Redact button (primary action)
                Button(action: sendToRedact) {
                    Label("Send to Redact", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.transcriptSegments.isEmpty)

            case .handedOff:
                // Status indicator
                Text("Sent to Redact")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func pauseSession() {
        sessionManager.pauseSession(session)
    }

    private func resumeSession() {
        Task {
            try? await sessionManager.resumeSession(session)
        }
    }

    private func stopSession() {
        Task {
            await sessionManager.stopSession(session)
        }
    }

    private func sendToRedact() {
        let transcript = sessionManager.handoffToRedact(session)
        NotificationCenter.default.post(
            name: .sessionHandoffToRedact,
            object: SessionHandoffPayload(
                sessionId: session.id,
                transcript: transcript,
                detectedEntities: session.detectedEntities,
                entityMapping: session.entityMapping
            )
        )
    }
}

// MARK: - Audio Level Meter

/// Simple audio level meter
struct AudioLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.2))

                // Level indicator
                Rectangle()
                    .fill(levelColor)
                    .frame(height: geometry.size.height * CGFloat(min(level * 5, 1.0)))
            }
        }
        .frame(width: 8, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private var levelColor: Color {
        if level > 0.7 {
            return .red
        } else if level > 0.4 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SessionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        SessionDetailView(
            session: LiveSession.sample,
            sessionManager: SessionManager.shared
        )
    }
}
#endif
