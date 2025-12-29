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

    // MARK: - Scene Configuration

    var body: some Scene {
        WindowGroup {
            MainContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 700)

        // Settings window (Cmd+,)
        Settings {
            SettingsContainerView()
        }
    }
}
