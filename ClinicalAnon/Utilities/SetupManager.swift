//
//  SetupManager.swift
//  ClinicalAnon
//
//  Purpose: Manages Ollama setup detection, installation, and state
//  Organization: 3 Big Things
//

import Foundation
import Combine
import AppKit

// MARK: - Setup States

enum SetupState: Equatable {
    case checking
    case ready
    case needsHomebrew
    case needsOllama
    case needsModel
    case downloadingModel(progress: Double)
    case startingOllama
    case error(String)
}

// MARK: - Setup Manager

@MainActor
class SetupManager: ObservableObject {

    // MARK: - Published Properties

    @Published var state: SetupState = .checking
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatus: String = ""

    // MARK: - Private Properties

    private var pollTimer: Timer?
    private let modelName = "llama3.1:8b"

    // MARK: - Initialization

    init() {
        // Start checking setup on initialization
        Task {
            await checkSetup()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Main Setup Check

    func checkSetup() async {
        state = .checking

        // Check Homebrew
        guard isHomebrewInstalled() else {
            state = .needsHomebrew
            return
        }

        // Check Ollama
        guard isOllamaInstalled() else {
            state = .needsOllama
            return
        }

        // Check if Ollama is running
        let running = await isOllamaRunning()
        if !running {
            // Try to start it automatically
            do {
                try startOllama()
                // Wait 2 seconds for startup
                try await Task.sleep(nanoseconds: 2_000_000_000)

                // Verify it started
                let nowRunning = await isOllamaRunning()
                if !nowRunning {
                    state = .error("Ollama failed to start. Please run 'ollama serve' manually.")
                    return
                }
            } catch {
                state = .error("Failed to start Ollama: \(error.localizedDescription)")
                return
            }
        }

        // Check if model is downloaded
        guard isModelDownloaded() else {
            state = .needsModel
            return
        }

        // Everything is ready!
        state = .ready
    }

    // MARK: - Homebrew Detection

    func isHomebrewInstalled() -> Bool {
        // Check common Homebrew installation paths
        let possiblePaths = [
            "/opt/homebrew/bin/brew",  // Apple Silicon
            "/usr/local/bin/brew"       // Intel Mac
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Fallback: try which command
        return executeCommand("/bin/bash", args: ["-c", "which brew"]) != nil
    }

    func copyHomebrewInstallCommand() {
        let command = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        copyToClipboard(command)
    }

    // MARK: - Ollama Installation

    func isOllamaInstalled() -> Bool {
        // Check common Ollama installation paths
        let possiblePaths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Fallback: try which command
        return executeCommand("/usr/bin/which", args: ["ollama"]) != nil
    }

    func installOllama() async throws {
        // Opens Terminal with pre-filled command
        let script = """
        tell application "Terminal"
            activate
            do script "brew install ollama && echo 'INSTALLATION_COMPLETE'"
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            throw AppError.ollamaInstallFailed
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)

        if error != nil {
            throw AppError.ollamaInstallFailed
        }

        // Start polling for completion
        startPollingForInstallation()
    }

    func copyOllamaInstallCommand() {
        copyToClipboard("brew install ollama")
    }

    private func startPollingForInstallation() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.isOllamaInstalled() == true {
                    self?.pollTimer?.invalidate()
                    await self?.checkSetup()
                }
            }
        }
    }

    // MARK: - Ollama Service

    func isOllamaRunning() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    func startOllama() throws {
        // Try to find Ollama in common locations
        let possiblePaths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]

        var ollamaPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                ollamaPath = path
                break
            }
        }

        guard let path = ollamaPath else {
            throw AppError.ollamaNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve"]

        // Run in background
        try process.run()

        state = .startingOllama
    }

    // MARK: - Model Management

    func isModelDownloaded(modelName: String? = nil) -> Bool {
        let model = modelName ?? self.modelName

        // Find ollama binary
        guard let ollamaPath = findOllamaBinary() else {
            return false
        }

        guard let output = executeCommand(ollamaPath, args: ["list"]) else {
            return false
        }

        return output.contains(model)
    }

    func downloadModel() async throws {
        state = .downloadingModel(progress: 0.0)
        downloadProgress = 0.0
        downloadStatus = "Starting download..."

        guard let ollamaPath = findOllamaBinary() else {
            throw AppError.ollamaNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ollamaPath)
        process.arguments = ["pull", modelName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Monitor progress in background
        Task.detached {
            let handle = pipe.fileHandleForReading

            while process.isRunning {
                let data = handle.availableData
                if data.count > 0, let line = String(data: data, encoding: .utf8) {
                    await MainActor.run {
                        self.downloadStatus = line.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Parse progress from output
                        if let progress = self.parseProgress(from: line) {
                            self.downloadProgress = progress
                            self.state = .downloadingModel(progress: progress)
                        }
                    }
                }

                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            // Success - recheck setup
            await checkSetup()
        } else {
            throw AppError.modelDownloadFailed
        }
    }

    // MARK: - Helper Methods

    private func findOllamaBinary() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try which command
        if let output = executeCommand("/usr/bin/which", args: ["ollama"]),
           !output.isEmpty {
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func executeCommand(_ command: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }

    private func parseProgress(from line: String) -> Double? {
        // Ollama output format examples:
        // "pulling manifest... 45%"
        // "pulling 8a29a5e6... 67%"

        let pattern = #"(\d+)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line),
              let percentage = Double(line[range]) else {
            return nil
        }

        return percentage / 100.0
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Preview Helper

#if DEBUG
extension SetupManager {
    static var preview: SetupManager {
        let manager = SetupManager()
        return manager
    }

    static var previewReady: SetupManager {
        let manager = SetupManager()
        Task { @MainActor in
            manager.state = .ready
        }
        return manager
    }

    static var previewNeedsOllama: SetupManager {
        let manager = SetupManager()
        Task { @MainActor in
            manager.state = .needsOllama
        }
        return manager
    }

    static var previewDownloading: SetupManager {
        let manager = SetupManager()
        Task { @MainActor in
            manager.state = .downloadingModel(progress: 0.45)
            manager.downloadProgress = 0.45
            manager.downloadStatus = "pulling manifest... 45%"
        }
        return manager
    }
}
#endif
