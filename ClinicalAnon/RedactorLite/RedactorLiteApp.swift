//
//  RedactorLiteApp.swift
//  Redactor Lite
//
//  Purpose: Simplified Redactor app — redact, copy out, paste back, restore.
//           No AI analysis, no live sessions.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Main App

@main
struct RedactorLiteApp: App {

    @StateObject private var viewModel = LiteViewModel()

    var body: some Scene {
        WindowGroup {
            LiteRedactorView(viewModel: viewModel)
                .frame(minWidth: 1100, minHeight: 600)
                .onOpenURL { url in
                    handleRecordingURL(url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 800)
        .commands {
            // Remove unused menu items
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            LiteSettingsView()
        }
    }

    // MARK: - URL Scheme Handler

    /// Handles `redactor-lite://record?initials=JB&type=Therapy&length=50&goals=...&multiSpeaker=false`
    private func handleRecordingURL(_ url: URL) {
        guard url.scheme == "redactor-lite",
              url.host == "record" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems ?? []

        var info: [String: String] = [:]
        for item in params {
            if let value = item.value {
                info[item.name] = value
            }
        }

        // Open recording window, then post notification with metadata params
        RecordingWindowController.shared.showRecordingWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(
                name: .autoStartRecording,
                object: nil,
                userInfo: info
            )
        }
    }
}

// MARK: - Lite Settings View

/// Settings — detection, exclusions, inclusions, and recording
struct LiteSettingsView: View {
    private enum Tab: String, Hashable {
        case detection = "Detection"
        case exclusions = "Exclusions"
        case inclusions = "Inclusions"
        case recording = "Recording"
    }

    @State private var selectedTab: Tab = .detection
    @StateObject private var coworkExport = CoworkExportService()

    var body: some View {
        TabView(selection: $selectedTab) {
            DetectionSettingsView()
                .tabItem { Label("Detection", systemImage: "magnifyingglass") }
                .tag(Tab.detection)

            ExclusionSettingsView()
                .tabItem { Label("Exclusions", systemImage: "minus.circle") }
                .tag(Tab.exclusions)

            InclusionSettingsView()
                .tabItem { Label("Inclusions", systemImage: "plus.circle") }
                .tag(Tab.inclusions)

            RecordingSettingsView(coworkExport: coworkExport)
                .tabItem { Label("Recording", systemImage: "mic.circle") }
                .tag(Tab.recording)
        }
        .frame(width: 500, height: 650)
    }
}
