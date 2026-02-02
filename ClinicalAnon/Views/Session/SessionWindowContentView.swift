//
//  SessionWindowContentView.swift
//  ClinicalAnon
//
//  Purpose: SwiftUI content view for the session window
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Window Content View

/// The SwiftUI content view displayed in the session window
struct SessionWindowContentView: View {

    // MARK: - Properties

    @StateObject private var sessionManager = SessionManager.shared
    @State private var selectedSession: LiveSession?
    @State private var sessionToName: LiveSession?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Session sidebar
            SessionSidebarView(
                sessionManager: sessionManager,
                selectedSession: $selectedSession
            )

            Divider()

            // Session detail or empty state
            if let session = selectedSession {
                SessionDetailView(
                    session: session,
                    sessionManager: sessionManager
                )
            } else {
                emptyStateView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(DesignSystem.Colors.background)
        .sessionNameSheet(session: $sessionToName, sessionManager: sessionManager)
        .onReceive(NotificationCenter.default.publisher(for: .sessionNeedsNaming)) { notification in
            if let sessionId = notification.object as? UUID,
               let session = sessionManager.sessions.first(where: { $0.id == sessionId }) {
                sessionToName = session
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionHandoffToRedact)) { notification in
            if let payload = notification.object as? SessionHandoffPayload {
                // Forward to main window with full payload
                NotificationCenter.default.post(
                    name: .sessionTranscriptReadyForRedact,
                    object: payload
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
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

// MARK: - Notification

extension Notification.Name {
    static let sessionTranscriptReadyForRedact = Notification.Name("sessionTranscriptReadyForRedact")
}

// MARK: - Preview

#if DEBUG
struct SessionWindowContentView_Previews: PreviewProvider {
    static var previews: some View {
        SessionWindowContentView()
            .frame(width: 700, height: 600)
    }
}
#endif
