//
//  RecordingWindowController.swift
//  Redactor Lite
//
//  Purpose: Manages the recording session window
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Recording Window Controller

final class RecordingWindowController {

    // MARK: - Shared Instance

    static let shared = RecordingWindowController()

    // MARK: - Properties

    private var recordingWindow: NSWindow?
    private var windowDelegate: RecordingWindowDelegate?

    private init() {}

    // MARK: - Public Methods

    /// Shows the recording window, creating it if needed
    func showRecordingWindow() {
        if let existingWindow = recordingWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            createRecordingWindow()
        }
    }

    var isWindowOpen: Bool {
        recordingWindow?.isVisible ?? false
    }

    func closeRecordingWindow() {
        recordingWindow?.close()
        recordingWindow = nil
    }

    // MARK: - Private Methods

    private func createRecordingWindow() {
        let contentView = RecordingWindowView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Recording Session"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 1100, height: 650))
        window.minSize = NSSize(width: 900, height: 500)

        // Position to the right of the main window if possible
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let sessionX = mainFrame.maxX + 20
            let sessionY = mainFrame.origin.y + (mainFrame.height - 650) / 2
            window.setFrameOrigin(NSPoint(x: sessionX, y: max(sessionY, 50)))
        } else {
            window.center()
        }

        window.isReleasedWhenClosed = false

        let delegate = RecordingWindowDelegate()
        delegate.controller = self
        self.windowDelegate = delegate
        window.delegate = delegate

        self.recordingWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Window Delegate

private class RecordingWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: RecordingWindowController?

    func windowWillClose(_ notification: Notification) {
        controller?.windowDidClose()
    }
}

extension RecordingWindowController {
    fileprivate func windowDidClose() {
        recordingWindow = nil
        // Deactivate HTTP session when window closes so stale sessions don't linger
        Task { @MainActor in
            CopilotHTTPServer.shared.deactivateSession()
        }
    }
}
