//
//  MainContentView.swift
//  Redactor
//
//  Purpose: Container view for the staged workflow
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Main Content View

/// Container view that shows the phase indicator and switches between phase views
struct MainContentView: View {

    // MARK: - Properties

    @EnvironmentObject var viewModel: WorkflowViewModel
    @StateObject private var sessionManager = SessionManager.shared
    @State private var selectedSession: LiveSession?
    @State private var sessionToName: LiveSession?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Session sidebar (when in session mode)
            if sessionManager.isSessionModeActive {
                SessionSidebarView(
                    sessionManager: sessionManager,
                    selectedSession: $selectedSession
                )

                Divider()
            }

            // Main content area
            VStack(spacing: 0) {
                // Header with app title and phase indicator
                headerView

                Divider()
                    .opacity(0.3)

                // Content based on mode
                if sessionManager.isSessionModeActive {
                    sessionContent
                } else {
                    phaseContent
                }
            }
        }
        .background(DesignSystem.Colors.background)
        .frame(minWidth: 1000, minHeight: 600)
        .sessionNameSheet(session: $sessionToName, sessionManager: sessionManager)
        .onReceive(NotificationCenter.default.publisher(for: .sessionNeedsNaming)) { notification in
            if let sessionId = notification.object as? UUID,
               let session = sessionManager.sessions.first(where: { $0.id == sessionId }) {
                sessionToName = session
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionHandoffToRedact)) { notification in
            if let (_, transcript) = notification.object as? (UUID, String) {
                handleSessionHandoff(transcript: transcript)
            }
        }
    }

    // MARK: - Session Content

    @ViewBuilder
    private var sessionContent: some View {
        if let session = selectedSession {
            SessionDetailView(
                session: session,
                sessionManager: sessionManager
            )
        } else {
            // Empty state when no session selected
            VStack(spacing: DesignSystem.Spacing.large) {
                Spacer()

                Image(systemName: "waveform.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.5))

                Text("Select a Session")
                    .font(DesignSystem.Typography.title)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text("Choose a session from the sidebar or start a new recording.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Session Handoff

    private func handleSessionHandoff(transcript: String) {
        // Exit session mode
        sessionManager.exitSessionMode()

        // Load transcript into Redact phase
        viewModel.inputText = transcript
        viewModel.currentPhase = .redact

        // Clear session selection
        selectedSession = nil
    }

    /// Returns the appropriate help content type based on current phase
    private var currentHelpContentType: HelpContentType {
        switch viewModel.currentPhase {
        case .redact: return .redactPhase
        case .improve: return .improvePhase
        case .restore: return .restorePhase
        }
    }

    /// Opens help window with current phase content
    private func showHelp() {
        HelpWindowController.shared.showHelp(contentType: currentHelpContentType)
    }

    // MARK: - Header View

    private var headerView: some View {
        ZStack {
            // Phase indicator or Session mode indicator centered
            if sessionManager.isSessionModeActive {
                Text("Live Session")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            } else {
                PhaseIndicator(viewModel: viewModel)
            }

            // Left-aligned buttons
            HStack {
                HelpButton(action: showHelp)

                // Session mode toggle
                Button(action: toggleSessionMode) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: sessionManager.isSessionModeActive ? "doc.text" : "waveform")
                        Text(sessionManager.isSessionModeActive ? "Workflow" : "Sessions")
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()
            }

            // Right-aligned buttons
            HStack {
                Spacer()

                if !sessionManager.isSessionModeActive {
                    if viewModel.result != nil || viewModel.hasGeneratedOutput || !viewModel.sourceDocuments.isEmpty || !viewModel.inputText.isEmpty {
                        Button(action: { viewModel.clearAll() }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Start Over")
                            }
                            .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Toggle Session Mode

    private func toggleSessionMode() {
        if sessionManager.isSessionModeActive {
            sessionManager.exitSessionMode()
            selectedSession = nil
        } else {
            sessionManager.enterSessionMode()
        }
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.currentPhase {
        case .redact:
            RedactPhaseView(viewModel: viewModel)
        case .improve:
            ImprovePhaseView(viewModel: viewModel)
        case .restore:
            RestorePhaseView(viewModel: viewModel)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MainContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainContentView()
            .environmentObject(WorkflowViewModel())
    }
}
#endif
