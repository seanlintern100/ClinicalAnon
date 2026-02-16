//
//  ExpiredSessionsSheet.swift
//  ClinicalAnon
//
//  Purpose: Per-session deletion modal for expired sessions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Expired Sessions Sheet

/// Sheet showing sessions pending deletion with per-session controls
struct ExpiredSessionsSheet: View {

    // MARK: - Properties

    @ObservedObject var sessionManager: SessionManager
    @Binding var sessions: [LiveSession]
    @Environment(\.dismiss) private var dismiss

    @State private var exportSession: LiveSession?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Session list
            if sessions.isEmpty {
                emptyView
            } else {
                sessionListView
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 480)
        .frame(minHeight: 200)
        .background(DesignSystem.Colors.surface)
        .sheet(item: $exportSession) { session in
            TranscriptExportView(session: session)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sessions Scheduled for Deletion")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("These sessions have exceeded the retention period.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Session List

    private var sessionListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
            .padding(.vertical, DesignSystem.Spacing.small)
        }
        .frame(maxHeight: 300)
    }

    private func sessionRow(_ session: LiveSession) -> some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Text(formattedDate(session.createdAt))
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Per-session actions
            HStack(spacing: DesignSystem.Spacing.small) {
                Button("Extend 7 Days") {
                    Task {
                        await sessionManager.extendRetention(for: session)
                        sessions.removeAll { $0.id == session.id }
                        if sessions.isEmpty { dismiss() }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.small)

                Button {
                    exportSession = session
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                .controlSize(.small)

                Button(role: .destructive) {
                    Task {
                        await sessionManager.deleteSession(session)
                        sessions.removeAll { $0.id == session.id }
                        if sessions.isEmpty { dismiss() }
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "checkmark.circle")
                .font(.title)
                .foregroundStyle(DesignSystem.Colors.primaryTeal)
            Text("All sessions handled.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") pending")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            if !sessions.isEmpty {
                Button("Delete All Expired", role: .destructive) {
                    Task {
                        let toDelete = sessions
                        sessions = []
                        for session in toDelete {
                            await sessionManager.deleteSession(session)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
