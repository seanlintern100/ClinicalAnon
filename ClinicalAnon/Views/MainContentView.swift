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
            // Phase indicator centered
            PhaseIndicator(viewModel: viewModel)

            // Left-aligned help button
            HStack {
                HelpButton(action: showHelp)
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
