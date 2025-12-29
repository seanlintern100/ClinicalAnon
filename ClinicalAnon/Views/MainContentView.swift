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

    @StateObject private var viewModel = WorkflowViewModel()

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

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            // App title
            Text("Redactor")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // Phase indicator centered
            PhaseIndicator(viewModel: viewModel)

            Spacer()

            // Clear/New button
            if viewModel.result != nil {
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
    }
}
#endif
