//
//  SessionSidebarView.swift
//  ClinicalAnon
//
//  Purpose: Sidebar showing session list and state indicators
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Sidebar View

/// Sidebar displaying all sessions with their current state
struct SessionSidebarView: View {

    // MARK: - Properties

    @ObservedObject var sessionManager: SessionManager
    @Binding var selectedSession: LiveSession?

    @State private var sessionToExportTranscript: LiveSession?
    @State private var sessionToExportAudio: LiveSession?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Session List
            if sessionManager.sessions.isEmpty {
                emptyStateView
            } else {
                sessionListView
            }
        }
        .frame(width: 260)
        .background(DesignSystem.Colors.surface)
        .sheet(item: $sessionToExportTranscript) { session in
            TranscriptExportView(session: session)
        }
        .sheet(item: $sessionToExportAudio) { session in
            AudioExportView(session: session)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            // New Recording button (prominent, teal)
            Button(action: startNewSession) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Recording")
                }
                .font(DesignSystem.Typography.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sessionManager.activeSession != nil)
            .help(sessionManager.activeSession != nil ? "Stop current session before starting a new one" : "Start a new recording session")

            // Sessions title
            HStack {
                Text("Sessions")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

            Text("No Sessions")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Start a new session to begin recording.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Session List

    private var sessionListView: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.xs) {
                ForEach(sessionManager.sessions) { session in
                    SessionRowView(
                        session: session,
                        isSelected: selectedSession?.id == session.id,
                        isActive: sessionManager.activeSession?.id == session.id
                    )
                    .onTapGesture {
                        selectedSession = session
                    }
                    .contextMenu {
                        sessionContextMenu(for: session)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.small)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func sessionContextMenu(for session: LiveSession) -> some View {
        if session.state == .complete {
            Button("Send to Redact") {
                sendToRedact(session)
            }

            Divider()

            Button("Export Transcript...") {
                sessionToExportTranscript = session
            }

            Button("Export Audio...") {
                sessionToExportAudio = session
            }
        }

        Button("Rename...") {
            // Trigger rename dialog
            NotificationCenter.default.post(
                name: .sessionNeedsNaming,
                object: session.id
            )
        }

        Divider()

        Button("Delete", role: .destructive) {
            deleteSession(session)
        }
    }

    // MARK: - Actions

    private func startNewSession() {
        Task {
            do {
                let session = try await sessionManager.startSession()
                selectedSession = session
            } catch {
                print("Failed to start session: \(error)")
            }
        }
    }

    private func sendToRedact(_ session: LiveSession) {
        let transcript = sessionManager.handoffToRedact(session)
        // Post notification with transcript for WorkflowViewModel to handle
        NotificationCenter.default.post(
            name: .sessionHandoffToRedact,
            object: (session.id, transcript)
        )
    }

    private func deleteSession(_ session: LiveSession) {
        Task {
            await sessionManager.deleteSession(session)
            if selectedSession?.id == session.id {
                selectedSession = nil
            }
        }
    }
}

// MARK: - Session Row View

/// Individual session row in the sidebar
struct SessionRowView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    let isSelected: Bool
    let isActive: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            // State indicator
            stateIndicator

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(session.state == .handedOff ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(session.formattedDuration)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if session.segmentCount > 0 {
                        Text("•")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("\(session.segmentCount) segments")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            // Recording indicator for active session
            if isActive && session.state == .recording {
                recordingIndicator
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    // MARK: - State Indicator

    @ViewBuilder
    private var stateIndicator: some View {
        Image(systemName: session.state.iconName)
            .font(.body)
            .foregroundStyle(stateColor)
    }

    private var stateColor: Color {
        switch session.state {
        case .recording:
            return .red
        case .paused:
            return .orange
        case .complete:
            return .green
        case .handedOff:
            return DesignSystem.Colors.textSecondary
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .modifier(PulsingModifier())
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let sessionHandoffToRedact = Notification.Name("sessionHandoffToRedact")
}

// MARK: - Preview

#if DEBUG
struct SessionSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SessionSidebarView(
            sessionManager: SessionManager.shared,
            selectedSession: .constant(nil)
        )
    }
}
#endif
