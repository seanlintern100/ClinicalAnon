//
//  HomeView.swift
//  Redactor Lite
//
//  Purpose: Landing page with client list, recording, and redaction navigation
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Navigation State

enum HomeNavigation: Equatable {
    case home
    case clientSessions(initials: String, folderURL: URL)
    case redaction

    static func == (lhs: HomeNavigation, rhs: HomeNavigation) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home): return true
        case (.redaction, .redaction): return true
        case let (.clientSessions(a, _), .clientSessions(b, _)): return a == b
        default: return false
        }
    }
}

// MARK: - Client Info

struct ClientInfo: Identifiable {
    var id: String { initials }
    let initials: String
    let sessionCount: Int
    let lastSessionDate: String?
    let folderURL: URL
}

// MARK: - Home View

struct HomeView: View {

    @State private var navigation: HomeNavigation = .home
    @State private var clients: [ClientInfo] = []
    @StateObject private var viewModel = LiteViewModel()

    var body: some View {
        Group {
            switch navigation {
            case .home:
                homeContent

            case let .clientSessions(initials, folderURL):
                ClientSessionsView(
                    initials: initials,
                    folderURL: folderURL,
                    onBack: { navigation = .home }
                )

            case .redaction:
                ZStack {
                    GradientPageBackground()

                    VStack(spacing: 0) {
                        // Back bar
                        HStack {
                            Button {
                                navigation = .home
                            } label: {
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
                        .padding(.horizontal, DesignSystem.Spacing.medium)
                        .padding(.top, DesignSystem.Spacing.small)
                        .padding(.bottom, DesignSystem.Spacing.xs)

                        LiteRedactorView(viewModel: viewModel)
                    }
                }
            }
        }
        .onAppear {
            loadClients()
        }
    }

    // MARK: - Home Content

    private var homeContent: some View {
        ZStack {
            GradientPageBackground()

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xlarge) {
                    // Header
                    VStack(spacing: DesignSystem.Spacing.small) {
                        Text("Redactor")
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primaryTeal)

                        Text("Clinical documentation, anonymised")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, DesignSystem.Spacing.xxlarge)

                    // Action cards
                    HStack(spacing: DesignSystem.Spacing.medium) {
                        actionCard(
                            title: "Start Recording",
                            subtitle: "Live session with transcription",
                            icon: "mic.fill",
                            color: DesignSystem.Colors.primaryTeal
                        ) {
                            RecordingWindowController.shared.showRecordingWindow()
                        }

                        actionCard(
                            title: "Start Redaction",
                            subtitle: "Paste and redact clinical notes",
                            icon: "doc.text.fill",
                            color: DesignSystem.Colors.primaryTeal
                        ) {
                            navigation = .redaction
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xlarge)

                    // Client list
                    if !clients.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                            Text("Recent Clients")
                                .font(DesignSystem.Typography.heading)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .padding(.horizontal, DesignSystem.Spacing.xlarge)

                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: DesignSystem.Spacing.medium)
                                ],
                                spacing: DesignSystem.Spacing.medium
                            ) {
                                ForEach(clients) { client in
                                    clientCard(client)
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.xlarge)
                        }
                    }

                    Spacer(minLength: DesignSystem.Spacing.xlarge)
                }
            }
        }
    }

    // MARK: - Action Card

    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                VStack(spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.large)
            .glassPanel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Client Card

    private func clientCard(_ client: ClientInfo) -> some View {
        Button {
            navigation = .clientSessions(initials: client.initials, folderURL: client.folderURL)
        } label: {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text(client.initials)
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("\(client.sessionCount) session\(client.sessionCount == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if let date = client.lastSessionDate {
                    Text("Last: \(date)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignSystem.Spacing.medium)
            .glassPanel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadClients() {
        let exportService = SessionExportService()
        let sessionsURL = exportService.workspaceURL.appendingPathComponent("Sessions", isDirectory: true)
        let fm = FileManager.default

        guard let clientFolders = try? fm.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [ClientInfo] = []
        for folder in clientFolders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let initials = folder.lastPathComponent

            // Count session subfolders
            guard let sessionFolders = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let sessions = sessionFolders.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            guard !sessions.isEmpty else { continue }

            // Find most recent session by folder name (yyyy-MM-dd_HHmm sorts lexically)
            let sorted = sessions.map { $0.lastPathComponent }.sorted().reversed()
            var lastDate: String? = nil
            if let mostRecent = sorted.first {
                // Parse "2026-03-17_1430" into "17 Mar 2026"
                let parts = mostRecent.components(separatedBy: "_")
                if parts.count >= 1 {
                    let datePart = parts[0]
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let date = formatter.date(from: datePart) {
                        let display = DateFormatter()
                        display.dateFormat = "d MMM yyyy"
                        lastDate = display.string(from: date)
                    }
                }
            }

            loaded.append(ClientInfo(
                initials: initials,
                sessionCount: sessions.count,
                lastSessionDate: lastDate,
                folderURL: folder
            ))
        }

        // Sort by most recent session (clients with recent sessions first)
        clients = loaded.sorted { ($0.lastSessionDate ?? "") > ($1.lastSessionDate ?? "") }
    }
}
