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
    @AppStorage(SettingsKeys.liveSessionEnabled) private var liveSessionEnabled: Bool = SettingsKeys.liveSessionEnabledDefault
    @AppStorage(SettingsKeys.aiAnalysisEnabled) private var aiAnalysisEnabled: Bool = SettingsKeys.aiAnalysisEnabledDefault

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with app title and phase indicator
            headerView

            Divider()
                .opacity(0.3)

            // Phase content
            phaseContent
        }
        .background(DesignSystem.Colors.background)
        .frame(minWidth: 1000, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .sessionTranscriptReadyForRedact)) { notification in
            if let payload = notification.object as? SessionHandoffPayload {
                handleSessionHandoff(payload: payload)
            }
        }
    }

    // MARK: - Session Handoff

    private func handleSessionHandoff(payload: SessionHandoffPayload) {
        // Load transcript into Redact phase
        viewModel.inputText = payload.transcript

        // Pre-populate entity mapping from live session
        // This ensures entities detected during live recording get consistent codes
        for entity in payload.detectedEntities {
            _ = viewModel.engine.entityMapping.getReplacementCode(
                for: entity.originalText,
                type: entity.type
            )
        }

        // Add detected entities to the Redact phase so they appear immediately
        // These go into customEntities since there's no detection result yet
        for entity in payload.detectedEntities {
            // Skip if already exists (by original text)
            let alreadyExists = viewModel.redactState.customEntities.contains {
                $0.originalText.lowercased() == entity.originalText.lowercased()
            }
            guard !alreadyExists else { continue }

            viewModel.redactState.customEntities.append(entity)
        }

        viewModel.currentPhase = .redact
    }

    /// Returns the appropriate help content type based on current phase
    private var currentHelpContentType: HelpContentType {
        switch viewModel.currentPhase {
        case .redact: return .redactPhase
        case .improve: return aiAnalysisEnabled ? .improvePhase : .pasteBackPhase
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
            // Phase indicator centered
            PhaseIndicator(viewModel: viewModel)

            // Left-aligned buttons
            HStack(spacing: DesignSystem.Spacing.small) {
                // Help button
                HelpButton(action: showHelp)

                // Sessions button (opens/shows session window)
                if liveSessionEnabled {
                    Button(action: { SessionWindowController.shared.showSessionWindow() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "waveform")
                            Text("Sessions")
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Spacer()
            }

            // Right-aligned buttons
            HStack {
                Spacer()

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
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.currentPhase {
        case .redact:
            RedactPhaseView(viewModel: viewModel)
        case .improve:
            if aiAnalysisEnabled {
                ImprovePhaseView(viewModel: viewModel)
            } else {
                PasteBackPhaseView(viewModel: viewModel)
            }
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
