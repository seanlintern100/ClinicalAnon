//
//  SessionSetupPanel.swift
//  Redactor Lite
//
//  Purpose: Left panel — session metadata form, recording controls, transfer
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Session Setup Panel

struct SessionSetupPanel: View {

    @Binding var phase: RecordingPhase
    @Binding var metadata: SessionMetadata
    @Binding var errorMessage: String?
    @Binding var showSettings: Bool

    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var transcriptionService: TranscriptionService
    @ObservedObject var coworkExport: CoworkExportService

    var onStartRecording: () -> Void
    var onStopRecording: () -> Void
    var onPauseRecording: () -> Void
    var onResumeRecording: () -> Void
    var onTransferToRedactor: () -> Void

    @State private var showModelDownload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                switch phase {
                case .setup:
                    setupView
                case .recording:
                    recordingView
                case .stopped:
                    stoppedView
                }
            }
            .padding(DesignSystem.Spacing.medium)
        }
    }

    // MARK: - Setup Phase

    private var setupView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Session Setup")
                .font(DesignSystem.Typography.heading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            // Client Initials
            VStack(alignment: .leading, spacing: 4) {
                Text("Client Initials")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                TextField("e.g. JB", text: $metadata.clientInitials)
                    .textFieldStyle(.roundedBorder)
            }

            // Session Type
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Type")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Picker("", selection: $metadata.sessionType) {
                    ForEach(SessionType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if metadata.sessionType == .other {
                    TextField("Describe session type", text: Binding(
                        get: { metadata.otherTypeDescription ?? "" },
                        set: { metadata.otherTypeDescription = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            // Session Date
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Date")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                DatePicker("", selection: $metadata.sessionDate, displayedComponents: .date)
                    .labelsHidden()
            }

            // Session Length
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Length (minutes)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Stepper(value: $metadata.sessionLengthMinutes, in: 10...180, step: 5) {
                    Text("\(metadata.sessionLengthMinutes) min")
                        .font(DesignSystem.Typography.body)
                }
            }

            // Session Goals
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Goals")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                TextEditor(text: $metadata.sessionGoals)
                    .font(DesignSystem.Typography.body)
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            }

            Divider()

            // Export Folder
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Folder")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                if let folderURL = coworkExport.exportRootFolderURL {
                    Text(folderURL.lastPathComponent)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose Folder...") {
                    selectExportFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Whisper Model Status
            modelStatusView

            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Start Button
            Button(action: onStartRecording) {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start Recording")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!canStartRecording)
        }
    }

    // MARK: - Recording Phase

    private var recordingView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Header
            HStack {
                Text("Recording")
                    .font(DesignSystem.Typography.heading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
            }

            // Metadata summary
            metadataSummary

            Divider()

            // Timer
            if let session = sessionManager.activeSession {
                HStack {
                    Image(systemName: session.state == .paused ? "pause.circle.fill" : "record.circle.fill")
                        .foregroundStyle(session.state == .paused ? .orange : .red)
                        .font(.title2)
                    Text(session.formattedDuration)
                        .font(.system(.title, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                // Audio levels
                VStack(spacing: 4) {
                    audioLevelBar(label: "Mic", level: sessionManager.microphoneLevel)
                    audioLevelBar(label: "Sys", level: sessionManager.systemLevel)
                }
            }

            // Export status
            if coworkExport.chunksExported > 0 {
                HStack {
                    Image(systemName: "doc.text")
                    Text("\(coworkExport.chunksExported) chunks exported")
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if let error = coworkExport.lastExportError {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Controls
            HStack(spacing: DesignSystem.Spacing.medium) {
                if sessionManager.activeSession?.state == .paused {
                    Button(action: onResumeRecording) {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onPauseRecording) {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: onStopRecording) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    // MARK: - Stopped Phase

    private var stoppedView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Session Complete")
                .font(DesignSystem.Typography.heading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            // Summary
            metadataSummary

            Divider()

            if let session = sessionManager.sessions.first(where: { $0.state == .complete || $0.state == .handedOff }) {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("Duration", session.formattedDuration)
                    summaryRow("Segments", "\(session.transcriptSegments.count)")
                    summaryRow("Entities", "\(session.detectedEntities.count)")
                    summaryRow("Chunks Exported", "\(coworkExport.chunksExported)")
                }
            }

            Spacer()

            Button(action: onTransferToRedactor) {
                HStack {
                    Image(systemName: "arrow.right.circle")
                    Text("Transfer to Redactor")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("New Session") {
                phase = .setup
                metadata = SessionMetadata.fromLastUsed()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private var canStartRecording: Bool {
        !metadata.clientInitials.trimmingCharacters(in: .whitespaces).isEmpty &&
        coworkExport.hasRootFolder
    }

    private var metadataSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            summaryRow("Client", metadata.clientInitials.uppercased())
            summaryRow("Type", metadata.sessionType.rawValue)
            summaryRow("Date", formattedDate)
            if !metadata.sessionGoals.isEmpty {
                summaryRow("Goals", metadata.sessionGoals)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(2)
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: metadata.sessionDate)
    }

    private func audioLevelBar(label: String, level: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .frame(width: 30, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignSystem.Colors.textSecondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level > 0.7 ? .red : level > 0.3 ? .green : .green.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(min(level, 1.0)))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Model Status

    private var modelStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcription Model")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            if transcriptionService.isModelLoaded {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(transcriptionService.loadedModelSize?.rawValue ?? "Ready")
                        .font(DesignSystem.Typography.caption)
                }
            } else if transcriptionService.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: max(0, transcriptionService.downloadProgress))
                    Text(transcriptionService.downloadStatus)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            } else if transcriptionService.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model...")
                        .font(DesignSystem.Typography.caption)
                }
            } else {
                Button("Download Model") {
                    Task {
                        try? await transcriptionService.downloadModel(size: transcriptionService.selectedModelSize)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Folder Picker

    private func selectExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Cowork Export Folder"
        panel.message = "Choose the root folder where session data will be saved"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            coworkExport.setRootFolder(url)
        }
    }
}
