//
//  SessionAssistantView.swift
//  ClinicalAnon
//
//  Purpose: Main container for AI session assistant with Parking Lot and Live Feed
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Assistant View

/// Main container for AI-powered session assistance
struct SessionAssistantView: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            HSplitView {
                // Parking Lot (left)
                ParkingLotView(assistantService: assistantService)
                    .frame(minWidth: 280, idealWidth: 320)

                // Live Feed (right)
                LiveFeedView(assistantService: assistantService)
                    .frame(minWidth: 200, idealWidth: 280)
            }
        }
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Title
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.Colors.primaryTeal)

                Text("Session Assistant")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            Spacer()

            // Analysis indicator
            if assistantService.state.isAnalysing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Analysing...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            } else if let lastAnalysis = assistantService.state.lastAnalysisTime {
                Text("Updated \(lastAnalysis, style: .relative) ago")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // Error indicator
            if let error = assistantService.state.lastAnalysisError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .help(error)
            }

            // Enable/Disable toggle
            Toggle(isOn: $assistantService.isEnabled) {
                Text("Enabled")
                    .font(DesignSystem.Typography.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
    }

}

// MARK: - Preview

#if DEBUG
struct SessionAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        SessionAssistantView(
            assistantService: SessionManager.shared.assistantService
        )
        .frame(width: 600, height: 500)
    }
}
#endif
