//
//  ClinicalAnonApp.swift
//  ClinicalAnon
//
//  Purpose: Main application entry point and window configuration
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Main App

@main
struct ClinicalAnonApp: App {

    // MARK: - Properties

    @StateObject private var setupManager = SetupManager()

    // MARK: - Scene Configuration

    var body: some Scene {
        WindowGroup {
            // Show setup wizard until ready
            if setupManager.state == .ready {
                // Main anonymization view
                #if ENABLE_AI_FEATURES
                AnonymizationView(
                    ollamaService: {
                        let service = OllamaService(mockMode: false)
                        service.modelName = setupManager.selectedModel
                        return service
                    }(),
                    setupManager: setupManager
                )
                #else
                AnonymizationView(
                    setupManager: setupManager
                )
                #endif
            } else {
                SetupView()
                    .environmentObject(setupManager)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 700)
    }
}

// MARK: - Temporary Content View (Phase 1)

struct ContentView: View {

    var body: some View {
        ZStack {
            // Background
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.large) {
                // Title
                Text("ClinicalAnon")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                // Subtitle
                Text("Privacy-first clinical text anonymization")
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                // Description
                Text("Phase 1: Project Setup & Design System")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()
                    .frame(height: DesignSystem.Spacing.xlarge)

                // Status card
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("✅ Phase 1 Progress")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.primaryTeal)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        StatusRow(completed: true, text: "Folder structure created")
                        StatusRow(completed: true, text: "DesignSystem.swift implemented")
                        StatusRow(completed: true, text: "AppError.swift created")
                        StatusRow(completed: true, text: "ClinicalAnonApp.swift entry point")
                        StatusRow(completed: false, text: "Fonts integration (pending)")
                        StatusRow(completed: false, text: "Xcode project configuration (pending)")
                    }
                }
                .padding(DesignSystem.Spacing.large)
                .frame(maxWidth: 500)
                .cardStyle()

                Spacer()

                // Footer
                Text("Organization: 3 Big Things")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.xxlarge)
        }
    }
}

// MARK: - Status Row Component

struct StatusRow: View {
    let completed: Bool
    let text: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                .font(.system(size: 16))

            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1200, height: 700)
    }
}
#endif
