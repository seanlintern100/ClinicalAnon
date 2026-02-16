//
//  SessionSettingsView.swift
//  ClinicalAnon
//
//  Purpose: Settings panel for session retention, storage, and security
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Session Settings View

/// Settings panel for session data retention and security
struct SessionSettingsView: View {

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.sessionRetentionEnabled) private var retentionEnabled = true
    @AppStorage(SettingsKeys.sessionRetentionDays) private var retentionDays = 7

    @State private var storageUsed: String = "Calculating..."
    @State private var showDeleteAllConfirmation = false
    @State private var isDeletingAll = false

    private let storageService = SessionStorageService.shared
    private let sessionManager: SessionManager

    // MARK: - Initialization

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    retentionSection
                    storageSection
                    securityAdvisorySection
                }
                .padding(DesignSystem.Spacing.medium)
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 400, height: 480)
        .background(DesignSystem.Colors.surface)
        .onAppear {
            updateStorageUsed()
        }
        .alert("Delete All Sessions", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
        } message: {
            Text("This will permanently delete all session data including transcripts and audio recordings. This action cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session Settings")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("Data retention and security")
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

    // MARK: - Retention Section

    private var retentionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Data Retention")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Toggle(isOn: $retentionEnabled) {
                Text("Auto-delete old sessions")
                    .font(DesignSystem.Typography.body)
            }
            .toggleStyle(.switch)

            if retentionEnabled {
                HStack {
                    Text("Delete sessions after")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Stepper(value: $retentionDays, in: 1...30) {
                        Text("\(retentionDays) day\(retentionDays == 1 ? "" : "s")")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.primaryTeal)
                            .monospacedDigit()
                    }
                }
            }

            Text("Recommended: 7 days. Sessions containing clinical data should not be stored longer than necessary.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Storage")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("Total storage used:")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text(storageUsed)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Button(action: { showDeleteAllConfirmation = true }) {
                HStack {
                    if isDeletingAll {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text("Delete All Sessions Now")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isDeletingAll)
        }
    }

    // MARK: - Security Advisory Section

    private var securityAdvisorySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Security")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(DesignSystem.Colors.primaryTeal)
                    .font(.title3)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Session data is encrypted at rest using AES-256 encryption with keys stored in the macOS Keychain.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("For maximum protection, ensure FileVault is enabled on this Mac (System Settings > Privacy & Security > FileVault). FileVault adds full-disk encryption for additional protection beyond app-level encryption.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.primaryTeal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Helpers

    private func updateStorageUsed() {
        let bytes = storageService.totalStorageUsed()
        storageUsed = SessionStorageService.formatBytes(bytes)
    }

    private func deleteAllSessions() {
        isDeletingAll = true
        Task {
            // Delete all sessions from manager (clears UI state)
            for session in sessionManager.sessions {
                await sessionManager.deleteSession(session)
            }
            updateStorageUsed()
            isDeletingAll = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SessionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SessionSettingsView(sessionManager: SessionManager.shared)
    }
}
#endif
