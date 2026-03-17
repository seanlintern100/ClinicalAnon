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
        .frame(width: 500, height: 500)
    }
}
