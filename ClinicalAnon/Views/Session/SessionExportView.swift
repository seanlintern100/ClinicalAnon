//
//  SessionExportView.swift
//  ClinicalAnon
//
//  Purpose: Export options sheet for session transcripts and audio
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Transcript Export View

/// Sheet for exporting session transcript
struct TranscriptExportView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .markdown
    @State private var includeRedactions: Bool = true
    @State private var showPIIWarning: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Options
            optionsView

            Divider()

            // Footer with buttons
            footerView
        }
        .frame(width: 360)
        .background(DesignSystem.Colors.surface)
        .alert("Export Contains PII", isPresented: $showPIIWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Export Anyway") {
                performExport()
            }
        } message: {
            Text("This export contains unredacted clinical information including patient names, dates, and other PII.\n\nOnly export to secure, authorized locations. Ensure compliance with your organization's data handling policies.")
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Transcript")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(session.displayName)
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

    // MARK: - Options

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Format picker
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Format")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Redaction toggle
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Content")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Toggle(isOn: $includeRedactions) {
                    HStack {
                        Image(systemName: includeRedactions ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(includeRedactions ? DesignSystem.Colors.primaryTeal : .orange)
                        Text(includeRedactions ? "Redacted (PII removed)" : "Unredacted (includes PII)")
                            .font(DesignSystem.Typography.body)
                    }
                }
                .toggleStyle(.switch)
            }

            // PII warning for unredacted
            if !includeRedactions {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("Unredacted export will include names, dates, and other personal information.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.small)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: handleExport) {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Export")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isExporting || session.transcriptSegments.isEmpty)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Actions

    private func handleExport() {
        if includeRedactions {
            performExport()
        } else {
            showPIIWarning = true
        }
    }

    private func performExport() {
        isExporting = true

        Task {
            do {
                let url = try await TranscriptExportService.shared.exportTranscript(
                    session: session,
                    format: format,
                    redacted: includeRedactions
                )
                print("Transcript exported to: \(url.path)")
                dismiss()
            } catch ExportError.cancelled {
                // User cancelled - just stop exporting
            } catch {
                exportError = error.localizedDescription
            }

            isExporting = false
        }
    }
}

// MARK: - Audio Export View

/// Sheet for exporting session audio (combined mic + system)
struct AudioExportView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting: Bool = false
    @State private var exportError: String?

    // MARK: - Computed Properties

    private var micChunks: [AudioChunkReference] {
        session.audioChunkPaths.filter { $0.stream == .microphone }
    }

    private var sysChunks: [AudioChunkReference] {
        session.audioChunkPaths.filter { $0.stream == .system }
    }

    private var totalSize: Int64 {
        session.audioChunkPaths.reduce(0) { $0 + $1.fileSize }
    }

    private var hasAudio: Bool {
        !session.audioChunkPaths.isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            contentView

            Divider()

            // Footer with buttons
            footerView
        }
        .frame(width: 360)
        .background(DesignSystem.Colors.surface)
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Audio")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(session.displayName)
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

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Audio summary
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("Audio Sources")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                // Mic audio
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(micChunks.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    Text("Microphone")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(micChunks.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    Spacer()
                    if micChunks.isEmpty {
                        Text("No audio")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: micChunks.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                // System audio
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(sysChunks.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    Text("System Audio")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(sysChunks.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                    Spacer()
                    if sysChunks.isEmpty {
                        Text("No audio")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: sysChunks.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            // Info box
            if hasAudio {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)

                    Text("Both audio sources will be mixed into a single file.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))

                // Security warning for audio exports
                HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("Audio recordings may contain identifiable patient information. Ensure this file is stored securely and in compliance with your organization's data handling policies.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.small)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: performExport) {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Export")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isExporting || !hasAudio)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Actions

    private func performExport() {
        isExporting = true

        Task {
            do {
                let url = try await TranscriptExportService.shared.exportCombinedAudio(session: session)
                print("Audio exported to: \(url.path)")
                dismiss()
            } catch ExportError.cancelled {
                // User cancelled - just stop exporting
            } catch {
                exportError = error.localizedDescription
            }

            isExporting = false
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SessionExportView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TranscriptExportView(session: .completed)
        }
        .frame(height: 400)
        .previewDisplayName("Transcript Export")

        VStack {
            AudioExportView(session: .completed)
        }
        .frame(height: 350)
        .previewDisplayName("Audio Export")
    }
}
#endif
