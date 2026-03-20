//
//  ClientSessionsView.swift
//  Redactor Lite
//
//  Purpose: Shows sessions for a selected client, loaded from filesystem
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Info

struct SessionInfo: Identifiable {
    var id: String { date }
    let date: String
    let displayDate: String
    let type: String
    let duration: Int
    let hasAnalysis: Bool
    let hasNotes: Bool
    let folderURL: URL
}

// MARK: - Client Sessions View

struct ClientSessionsView: View {

    let initials: String
    let folderURL: URL
    let onBack: () -> Void

    @State private var sessions: [SessionInfo] = []
    @State private var selectedSession: SessionInfo?

    var body: some View {
        ZStack {
            GradientPageBackground()

            if let session = selectedSession {
                // Notes view for selected session
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Button {
                            selectedSession = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Sessions")
                                    .font(DesignSystem.Typography.button)
                            }
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.large)
                    .padding(.top, DesignSystem.Spacing.medium)

                    ClinicalNotesView(
                        sessionFolder: session.folderURL,
                        privateFolderURL: privateFolderURL
                    )
                }
            } else {
                // Session list
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Home")
                                    .font(DesignSystem.Typography.button)
                            }
                            .foregroundColor(DesignSystem.Colors.primaryTeal)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.large)
                    .padding(.top, DesignSystem.Spacing.medium)

                    Text("Sessions for \(initials)")
                        .font(DesignSystem.Typography.heading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, DesignSystem.Spacing.large)
                        .padding(.top, DesignSystem.Spacing.medium)
                        .padding(.bottom, DesignSystem.Spacing.medium)

                    if sessions.isEmpty {
                        VStack {
                            Spacer()
                            Text("No sessions found")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: DesignSystem.Spacing.medium) {
                                ForEach(sessions) { session in
                                    sessionCard(session)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.large)
                            .padding(.bottom, DesignSystem.Spacing.large)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadSessions()
        }
    }

    /// Derive Private/{initials}/ path from the client folder URL
    private var privateFolderURL: URL {
        // folderURL is Sessions/{initials}/, workspace root is 2 levels up
        let workspaceRoot = folderURL
            .deletingLastPathComponent()  // remove {initials}
            .deletingLastPathComponent()  // remove "Sessions"
        return workspaceRoot
            .appendingPathComponent("Private", isDirectory: true)
            .appendingPathComponent(initials, isDirectory: true)
    }

    // MARK: - Session Card

    private func sessionCard(_ session: SessionInfo) -> some View {
        Button {
            if session.hasNotes {
                selectedSession = session
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.medium) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(session.displayDate)
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    HStack(spacing: DesignSystem.Spacing.small) {
                        Text(session.type)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)

                        if session.duration > 0 {
                            Text("\(session.duration) min")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                if session.hasNotes {
                    Label("Notes", systemImage: "doc.text.fill")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primaryTeal)
                }

                if session.hasAnalysis {
                    Label("Analysed", systemImage: "checkmark.circle.fill")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primaryTeal)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .glassPanel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadSessions() {
        let fm = FileManager.default

        guard let sessionFolders = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [SessionInfo] = []
        for folder in sessionFolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }

            let folderName = folder.lastPathComponent  // e.g. "2026-03-17_1430"

            // Parse date from folder name
            var displayDate = folderName
            let parts = folderName.components(separatedBy: "_")
            if parts.count >= 2 {
                let datePart = parts[0]
                let timePart = parts[1]
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: datePart) {
                    let display = DateFormatter()
                    display.dateFormat = "EEEE d MMM yyyy"
                    displayDate = display.string(from: date)

                    // Append time
                    if timePart.count == 4 {
                        let hour = String(timePart.prefix(2))
                        let minute = String(timePart.suffix(2))
                        displayDate += " at \(hour):\(minute)"
                    }
                }
            }

            // Read session_info.json
            var sessionType = ""
            var duration = 0
            let infoURL = folder.appendingPathComponent("session_info.json")
            if let data = try? Data(contentsOf: infoURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sessionType = (json["session_type"] as? String)?.capitalized ?? ""
                duration = json["session_duration_minutes"] as? Int ?? 0
            }

            // Check for session_state.json (analysis data)
            let stateURL = folder.appendingPathComponent("session_state.json")
            let hasAnalysis = fm.fileExists(atPath: stateURL.path)

            // Check for clinical_notes.json
            let notesURL = folder.appendingPathComponent("clinical_notes.json")
            let hasNotes = fm.fileExists(atPath: notesURL.path)

            loaded.append(SessionInfo(
                date: folderName,
                displayDate: displayDate,
                type: sessionType,
                duration: duration,
                hasAnalysis: hasAnalysis,
                hasNotes: hasNotes,
                folderURL: folder
            ))
        }

        // Sort newest first
        sessions = loaded.sorted { $0.date > $1.date }
    }
}
