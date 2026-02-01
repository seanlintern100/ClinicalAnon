//
//  SessionWindowController.swift
//  ClinicalAnon
//
//  Purpose: Manages a resizable session window that can sit alongside the main app
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Session Window Controller

/// Singleton controller that manages the session window
final class SessionWindowController {

    // MARK: - Shared Instance

    static let shared = SessionWindowController()

    // MARK: - Properties

    private var sessionWindow: NSWindow?
    private var windowDelegate: SessionWindowDelegate?

    private init() {}

    // MARK: - Public Methods

    /// Shows the session window, creating it if needed
    func showSessionWindow() {
        if let existingWindow = sessionWindow, existingWindow.isVisible {
            // Window already open - bring to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Create new window
            createSessionWindow()
        }
    }

    /// Returns whether the session window is currently open
    var isWindowOpen: Bool {
        sessionWindow?.isVisible ?? false
    }

    /// Closes the session window if open
    func closeSessionWindow() {
        sessionWindow?.close()
        sessionWindow = nil
    }

    // MARK: - Private Methods

    private func createSessionWindow() {
        let contentView = SessionWindowContentView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Live Session"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 700, height: 600))
        window.minSize = NSSize(width: 500, height: 400)

        // Position to the right of the main window if possible
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let sessionX = mainFrame.maxX + 20
            let sessionY = mainFrame.origin.y + (mainFrame.height - 600) / 2
            window.setFrameOrigin(NSPoint(x: sessionX, y: max(sessionY, 50)))
        } else {
            window.center()
        }

        window.isReleasedWhenClosed = false

        // Set up delegate
        let delegate = SessionWindowDelegate()
        delegate.controller = self
        self.windowDelegate = delegate
        window.delegate = delegate

        self.sessionWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Window Delegate

private class SessionWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: SessionWindowController?

    func windowWillClose(_ notification: Notification) {
        controller?.windowDidClose()
    }
}

extension SessionWindowController {
    fileprivate func windowDidClose() {
        sessionWindow = nil
    }
}
