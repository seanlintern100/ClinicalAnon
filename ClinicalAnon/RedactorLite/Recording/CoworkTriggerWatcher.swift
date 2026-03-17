//
//  CoworkTriggerWatcher.swift
//  Redactor Lite
//
//  Purpose: Watches the Cowork export folder for .cowork_trigger.json files.
//           When found, opens recording window with pre-filled metadata and auto-starts.
//           This allows Cowork (running in a Linux VM) to launch recording sessions
//           by writing a JSON file to the shared workspace folder.
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Trigger JSON Model

struct CoworkTrigger: Codable {
    let initials: String
    let type: String?
    let otherType: String?
    let length: Int?
    let goals: String?
    let multiSpeaker: Bool?
}

// MARK: - Cowork Trigger Watcher

@MainActor
final class CoworkTriggerWatcher {

    // MARK: - Shared Instance

    static let shared = CoworkTriggerWatcher()

    // MARK: - Properties

    private var pollTimer: Timer?
    private var isRunning = false

    /// The filename Cowork writes to trigger a recording session
    private static let triggerFilename = ".cowork_trigger.json"

    private init() {}

    // MARK: - Public Methods

    /// Start watching the Cowork export root folder for trigger files.
    /// Polls every 2 seconds. Safe to call multiple times — only one timer runs.
    func startWatching() {
        guard !isRunning else { return }
        isRunning = true
        print("[CoworkTriggerWatcher] Started watching for trigger files")

        // Log which folder we're watching
        logWatchedFolder()

        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForTrigger()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Stop watching for trigger files
    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
    }

    // MARK: - Private Methods

    private func logWatchedFolder() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "cowork.exportFolderBookmark") else {
            print("[CoworkTriggerWatcher] WARNING: No export folder bookmark set")
            return
        }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            print("[CoworkTriggerWatcher] Watching folder: \(url.path)")
        }
    }

    private func checkForTrigger() {
        // Get the export root folder from UserDefaults bookmark
        guard let bookmarkData = UserDefaults.standard.data(forKey: "cowork.exportFolderBookmark") else {
            return
        }

        var isStale = false
        guard let rootURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        guard rootURL.startAccessingSecurityScopedResource() else { return }
        defer { rootURL.stopAccessingSecurityScopedResource() }

        let triggerURL = rootURL.appendingPathComponent(Self.triggerFilename)

        guard FileManager.default.fileExists(atPath: triggerURL.path) else { return }

        // Read and parse the trigger file
        do {
            let data = try Data(contentsOf: triggerURL)
            let trigger = try JSONDecoder().decode(CoworkTrigger.self, from: data)

            // Delete trigger file immediately to prevent re-processing
            try? FileManager.default.removeItem(at: triggerURL)

            // Build notification userInfo matching the URL scheme format
            var info: [String: String] = [
                "initials": trigger.initials
            ]
            if let type = trigger.type {
                info["type"] = type
            }
            if let otherType = trigger.otherType {
                info["otherType"] = otherType
            }
            if let length = trigger.length {
                info["length"] = String(length)
            }
            if let goals = trigger.goals {
                info["goals"] = goals
            }
            if let multi = trigger.multiSpeaker {
                info["multiSpeaker"] = multi ? "true" : "false"
            }

            // Open recording window and trigger auto-start
            RecordingWindowController.shared.showRecordingWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: .autoStartRecording,
                    object: nil,
                    userInfo: info
                )
            }

        } catch {
            // If parsing fails, delete the malformed file and log
            try? FileManager.default.removeItem(at: triggerURL)
            print("[CoworkTriggerWatcher] Failed to parse trigger file: \(error)")
        }
    }
}
