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
            Text("This transcript contains unredacted personal information including names, dates, and other sensitive data.\n\nOnly export unredacted content if you have appropriate authorization and secure storage.")
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
                let url = try await SessionExportService.shared.exportTranscript(
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

/// Sheet for exporting session audio
struct AudioExportView: View {

    // MARK: - Properties

    @ObservedObject var session: LiveSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStream: AudioStream = .microphone
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

    // MARK: - Options

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Stream picker
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Audio Source")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                ForEach(AudioStream.allCases, id: \.self) { stream in
                    streamOption(stream)
                }
            }

            // Audio info
            if let info = audioInfo(for: selectedStream) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.primaryTeal)

                    Text(info)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Stream Option

    private func streamOption(_ stream: AudioStream) -> some View {
        let chunks = session.audioChunkPaths.filter { $0.stream == stream }
        let hasAudio = !chunks.isEmpty
        let totalSize = chunks.reduce(0) { $0 + $1.fileSize }

        return Button(action: {
            if hasAudio {
                selectedStream = stream
            }
        }) {
            HStack {
                Image(systemName: selectedStream == stream ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedStream == stream ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)

                Image(systemName: stream.iconName)
                    .foregroundStyle(hasAudio ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)

                Text(stream.displayName)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(hasAudio ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)

                Spacer()

                if hasAudio {
                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    Text("No audio")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                    .fill(selectedStream == stream ? DesignSystem.Colors.primaryTeal.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasAudio)
    }

    // MARK: - Audio Info

    private func audioInfo(for stream: AudioStream) -> String? {
        let chunks = session.audioChunkPaths.filter { $0.stream == stream }
        guard !chunks.isEmpty else { return nil }

        if chunks.count == 1 {
            return "Single audio file will be exported"
        } else {
            return "\(chunks.count) audio chunks will be merged into one file"
        }
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
            .disabled(isExporting || !hasSelectedAudio)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    private var hasSelectedAudio: Bool {
        !session.audioChunkPaths.filter { $0.stream == selectedStream }.isEmpty
    }

    // MARK: - Actions

    private func performExport() {
        isExporting = true

        Task {
            do {
                let url = try await SessionExportService.shared.exportAudio(
                    session: session,
                    stream: selectedStream
                )
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
