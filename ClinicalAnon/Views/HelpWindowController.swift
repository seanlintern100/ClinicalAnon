//
//  HelpWindowController.swift
//  ClinicalAnon
//
//  Purpose: Manages a resizable help window that can sit alongside the main app
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Help Window Controller

/// Singleton controller that manages the help window
final class HelpWindowController {

    // MARK: - Shared Instance

    static let shared = HelpWindowController()

    // MARK: - Properties

    private var helpWindow: NSWindow?
    private var currentContentType: HelpContentType = .fullGuide
    private var windowDelegate: HelpWindowDelegate?

    private init() {}

    // MARK: - Public Methods

    /// Shows the help window with the specified content type
    /// If window is already open, brings it to front and updates content
    func showHelp(contentType: HelpContentType) {
        currentContentType = contentType

        if let existingWindow = helpWindow, existingWindow.isVisible {
            // Window already open - bring to front and update content
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            updateContent(contentType: contentType)
        } else {
            // Create new window
            createHelpWindow(contentType: contentType)
        }
    }

    /// Closes the help window if open
    func closeHelp() {
        helpWindow?.close()
        helpWindow = nil
    }

    // MARK: - Private Methods

    private func createHelpWindow(contentType: HelpContentType) {
        let contentView = HelpWindowContentView(
            contentType: contentType,
            onContentTypeChange: { [weak self] newType in
                self?.currentContentType = newType
            }
        )

        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Redactor Help"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 500, height: 600))
        window.minSize = NSSize(width: 400, height: 400)
        window.maxSize = NSSize(width: 800, height: 1200)

        // Position to the right of the main window if possible
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let helpX = mainFrame.maxX + 20
            let helpY = mainFrame.origin.y + (mainFrame.height - 600) / 2
            window.setFrameOrigin(NSPoint(x: helpX, y: max(helpY, 50)))
        } else {
            window.center()
        }

        window.isReleasedWhenClosed = false

        // Set up delegate
        let delegate = HelpWindowDelegate()
        delegate.controller = self
        self.windowDelegate = delegate
        window.delegate = delegate

        self.helpWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func updateContent(contentType: HelpContentType) {
        guard let window = helpWindow else { return }

        let contentView = HelpWindowContentView(
            contentType: contentType,
            onContentTypeChange: { [weak self] newType in
                self?.currentContentType = newType
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        window.contentViewController = hostingController
    }
}

// MARK: - Window Delegate

private class HelpWindowDelegate: NSObject, NSWindowDelegate {
    weak var controller: HelpWindowController?

    func windowWillClose(_ notification: Notification) {
        controller?.windowDidClose()
    }
}

extension HelpWindowController {
    fileprivate func windowDidClose() {
        helpWindow = nil
    }
}

// MARK: - Help Window Content View

/// The SwiftUI content view displayed in the help window
struct HelpWindowContentView: View {

    @State var contentType: HelpContentType
    var onContentTypeChange: ((HelpContentType) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar for switching between guides
            navigationBar

            Divider()

            // Scrollable content
            ScrollView {
                MarkdownRenderer(markdown: contentType.content)
                    .padding(DesignSystem.Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text(contentType.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // Phase navigation buttons
            Picker("", selection: $contentType) {
                Text("Full Guide").tag(HelpContentType.fullGuide)
                Text("Redact").tag(HelpContentType.redactPhase)
                Text("Improve").tag(HelpContentType.improvePhase)
                Text("Restore").tag(HelpContentType.restorePhase)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .onChange(of: contentType) { newValue in
                onContentTypeChange?(newValue)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Preview

#if DEBUG
struct HelpWindowContentView_Previews: PreviewProvider {
    static var previews: some View {
        HelpWindowContentView(contentType: .redactPhase)
            .frame(width: 500, height: 600)
    }
}
#endif
