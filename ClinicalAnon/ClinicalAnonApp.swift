//
//  ClinicalAnonApp.swift
//  ClinicalAnon
//
//  Purpose: Main application entry point and window configuration
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - App Delegate for Quit Protection

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if a model download is in progress
        if DownloadStateManager.shared.isDownloading {
            // Show warning alert
            let alert = NSAlert()
            alert.messageText = "Download in Progress"
            alert.informativeText = "A model is currently downloading. Quitting now will cancel the download and you'll need to restart it next time.\n\nAre you sure you want to quit?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue Download")
            alert.addButton(withTitle: "Quit Anyway")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // User chose to continue download
                return .terminateCancel
            } else {
                // User chose to quit anyway - clean up
                DownloadStateManager.shared.endDownload()
                return .terminateNow
            }
        }

        return .terminateNow
    }
}

// MARK: - Main App

@main
struct ClinicalAnonApp: App {

    // MARK: - Properties

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
        .commands {
            // Help menu
            CommandGroup(replacing: .help) {
                Button("Redactor User Guide") {
                    HelpWindowController.shared.showHelp(contentType: .fullGuide)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        // Settings window (Cmd+,)
        Settings {
            SettingsContainerView()
        }
    }
}
