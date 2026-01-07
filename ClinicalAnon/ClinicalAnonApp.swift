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

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = WorkflowViewModel()

    // MARK: - Scene Configuration

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(viewModel)
                .task {
                    // Clear any stale memory files from previous session
                    viewModel.improveState.resetMemoryModeOnLaunch()

                    // Pre-load models in background (only if already cached)
                    await LocalLLMService.shared.preloadIfCached()
                    await XLMRobertaNERService.shared.preloadIfCached()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Clear memory storage on app termination (security hardening)
                    viewModel.improveState.resetMemoryModeOnLaunch()
                    viewModel.clearAll()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 700)
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // Clear sensitive data when app goes to background
                viewModel.clearAll()
            }
        }

        // Settings window (Cmd+,)
        Settings {
            SettingsContainerView()
        }
    }
}
