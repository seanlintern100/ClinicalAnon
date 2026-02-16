//
//  TranscriptionSettingsView.swift
//  Redactor
//
//  Purpose: Settings UI for Whisper model selection and download management
//  Organization: 3 Big Things
//

import SwiftUI

struct TranscriptionSettingsView: View {

    @StateObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var downloadState = DownloadStateManager.shared

    var body: some View {
        Form {
            // Status Section
            Section {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.body)
                }

                if let error = transcriptionService.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("WhisperKit provides on-device speech-to-text transcription. Models run entirely on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Model Selection
            Section {
                ForEach(WhisperModelSize.allCases) { modelSize in
                    modelRow(modelSize)
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Larger models are more accurate but use more memory and take longer to process. Medium is recommended for most users.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Model Status Section
            Section {
                modelStatusContent
            } header: {
                Text("Model Status")
            }

            // Audio Capture Section
            Section {
                Toggle(isOn: $voiceProcessingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Echo Cancellation")
                            .font(.body)
                        Text("Remove speaker audio from microphone recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $noiseSuppressionEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Noise Suppression")
                            .font(.body)
                        Text("Reduce background noise (fan, typing, HVAC)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $vadEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Activity Detection")
                            .font(.body)
                        Text("Skip transcription during silence to reduce hallucinations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Audio Capture")
            } footer: {
                Text("Echo cancellation removes speaker audio from your microphone. Noise suppression filters background noise. Voice activity detection helps prevent phantom words during silence. All settings require restarting a session to take effect.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Speaker Identification Section
            Section {
                Toggle(isOn: $enhancedDiarizationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enhanced Speaker Identification")
                            .font(.body)
                        Text("Distinguish multiple remote participants by voice")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Speaker Identification")
            } footer: {
                Text("When enabled, remote audio is analyzed to identify distinct speakers (e.g., Patient A, Patient B). Useful for group sessions. Adds processing time per chunk. All processing is on-device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Data Retention Section
            Section {
                Toggle(isOn: $retentionEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-delete old sessions")
                            .font(.body)
                        Text("Automatically remove sessions after the retention period")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if retentionEnabled {
                    HStack {
                        Text("Delete sessions after")
                            .font(.body)

                        Stepper(value: $retentionDays, in: 1...30) {
                            Text("\(retentionDays) day\(retentionDays == 1 ? "" : "s")")
                                .font(.body)
                                .foregroundColor(.accentColor)
                                .monospacedDigit()
                        }
                    }

                    retentionTimelineView
                }
            } header: {
                Text("Data Retention")
            } footer: {
                Text("Recommended: 7 days. Sessions containing clinical data should not be stored longer than necessary.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Storage Section
            Section {
                HStack {
                    Text("Total storage used")
                        .font(.body)
                    Spacer()
                    Text(storageUsed)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Button(role: .destructive) {
                    showDeleteAllConfirmation = true
                } label: {
                    HStack {
                        if isDeletingAll {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Delete All Sessions Now")
                    }
                }
                .disabled(isDeletingAll)
            } header: {
                Text("Session Storage")
            }

            // Security Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Session data encrypted at rest (AES-256)", systemImage: "lock.shield")
                    Label("Encryption keys stored in macOS Keychain", systemImage: "key")
                    Label("Audio chunks encrypted after recording", systemImage: "waveform.badge.exclamationmark")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Security")
            } footer: {
                Text("For maximum protection, ensure FileVault is enabled (System Settings > Privacy & Security > FileVault).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { updateStorageUsed() }
        .alert("Delete All Sessions", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
        } message: {
            Text("This will permanently delete all session data including transcripts and audio recordings. This action cannot be undone.")
        }
    }

    // MARK: - Audio Settings

    @AppStorage(SettingsKeys.voiceProcessingEnabled) private var voiceProcessingEnabled: Bool = true
    @AppStorage(SettingsKeys.noiseSuppressionEnabled) private var noiseSuppressionEnabled: Bool = true
    @AppStorage(SettingsKeys.vadEnabled) private var vadEnabled: Bool = true
    @AppStorage(SettingsKeys.enhancedDiarizationEnabled) private var enhancedDiarizationEnabled: Bool = false

    // MARK: - Session Retention Settings

    @AppStorage(SettingsKeys.sessionRetentionEnabled) private var retentionEnabled = true
    @AppStorage(SettingsKeys.sessionRetentionDays) private var retentionDays = 7
    @State private var storageUsed: String = "Calculating..."
    @State private var showDeleteAllConfirmation = false
    @State private var isDeletingAll = false

    // MARK: - Retention Timeline

    private var retentionTimelineView: some View {
        let warningStart = max(retentionDays - 2, 0)
        let promptStart = retentionDays
        let autoDeleteStart = retentionDays + 7

        return VStack(alignment: .leading, spacing: 6) {
            timelineRow(
                color: .green,
                label: "Day 1\(warningStart > 1 ? " – \(warningStart)" : "")",
                description: "Active — no indicators"
            )
            if warningStart < promptStart {
                timelineRow(
                    color: .orange,
                    label: "Day \(warningStart + 1) – \(promptStart)",
                    description: "Warning badge shown in sidebar"
                )
            }
            timelineRow(
                color: .red,
                label: "Day \(promptStart + 1) – \(autoDeleteStart)",
                description: "Deletion prompt on app launch"
            )
            timelineRow(
                color: .secondary,
                label: "Day \(autoDeleteStart + 1)+",
                description: "Automatically deleted"
            )
        }
        .padding(.vertical, 4)
    }

    private func timelineRow(color: Color, label: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        if transcriptionService.isModelLoaded {
            return .green
        } else if transcriptionService.isDownloading || downloadState.isDownloading {
            return .blue
        } else if transcriptionService.isModelCached(size: transcriptionService.selectedModelSize) {
            return .blue
        } else {
            return .yellow
        }
    }

    private var statusText: String {
        if transcriptionService.isModelLoaded {
            if let loaded = transcriptionService.loadedModelSize {
                return "Model Loaded (\(loaded.displayName))"
            }
            return "Model Loaded"
        } else if transcriptionService.isDownloading || downloadState.isDownloading {
            return "Downloading..."
        } else if transcriptionService.isModelCached(size: transcriptionService.selectedModelSize) {
            return "Downloaded (Not Loaded)"
        } else {
            return "Not Downloaded"
        }
    }

    // MARK: - Model Row

    private func modelRow(_ modelSize: WhisperModelSize) -> some View {
        let isSelected = transcriptionService.selectedModelSize == modelSize
        let isCached = transcriptionService.isModelCached(size: modelSize)
        let isLoaded = transcriptionService.loadedModelSize == modelSize

        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(modelSize.displayName)
                        .font(.body)

                    if modelSize.isBundled {
                        Text("Bundled")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    } else {
                        Text(modelSize.sizeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if isLoaded {
                        Text("Loaded")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if isCached && !modelSize.isBundled {
                        Text("Cached")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !transcriptionService.isDownloading && !downloadState.isDownloading {
                transcriptionService.selectedModelSize = modelSize
            }
        }
    }

    // MARK: - Model Status Content

    @ViewBuilder
    private var modelStatusContent: some View {
        let selectedSize = transcriptionService.selectedModelSize
        let isCached = transcriptionService.isModelCached(size: selectedSize)
        let isLoaded = transcriptionService.loadedModelSize == selectedSize

        if transcriptionService.isDownloading || downloadState.isDownloading {
            VStack(alignment: .leading, spacing: 8) {
                Text(transcriptionService.downloadStatus.isEmpty ? downloadState.downloadStatus : transcriptionService.downloadStatus)
                    .font(.body)

                // Show indeterminate spinner when progress is negative, otherwise show progress bar
                if transcriptionService.downloadProgress < 0 {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: max(transcriptionService.downloadProgress, downloadState.downloadProgress))
                        .progressViewStyle(.linear)
                    Text("\(Int(max(transcriptionService.downloadProgress, downloadState.downloadProgress) * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Please don't quit the app during download.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } else if isLoaded {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Model Ready")
                            .font(.body)
                    }
                    Text("\(selectedSize.displayName) is loaded and ready for transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Unload") {
                    transcriptionService.unloadModel()
                }
            }
        } else if isCached {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Model Downloaded")
                        .font(.body)
                }
                Text("\(selectedSize.displayName) is ready to load")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Load Model") {
                        loadModel()
                    }
                    .buttonStyle(.borderedProminent)

                    if !selectedSize.isBundled {
                        Button("Delete") {
                            deleteModel()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected: \(selectedSize.displayName)")
                    .font(.body)
                Text("The model will download automatically when first used, or you can download now.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Download & Load Model") {
                    downloadModel()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Session Helpers

    private func updateStorageUsed() {
        let bytes = SessionStorageService.shared.totalStorageUsed()
        storageUsed = SessionStorageService.formatBytes(bytes)
    }

    private func deleteAllSessions() {
        isDeletingAll = true
        Task {
            let manager = SessionManager.shared
            for session in manager.sessions {
                await manager.deleteSession(session)
            }
            updateStorageUsed()
            isDeletingAll = false
        }
    }

    // MARK: - Actions

    private func loadModel() {
        Task {
            do {
                try await transcriptionService.loadModel(size: transcriptionService.selectedModelSize)
            } catch {
                // Error captured in transcriptionService.error
            }
        }
    }

    private func downloadModel() {
        Task {
            do {
                try await transcriptionService.downloadModel(size: transcriptionService.selectedModelSize)
            } catch {
                // Error captured in transcriptionService.error
            }
        }
    }

    private func deleteModel() {
        do {
            try transcriptionService.deleteModel(size: transcriptionService.selectedModelSize)
        } catch {
            // Handle error silently
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TranscriptionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptionSettingsView()
            .frame(width: 500, height: 450)
    }
}
#endif
