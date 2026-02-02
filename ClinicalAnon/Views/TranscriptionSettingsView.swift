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
                Text("When enabled, remote audio is analyzed to identify distinct speakers (e.g., Patient A, Patient B). Useful for group sessions. Adds ~1 second processing time per minute of audio. All processing is on-device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Audio Settings

    @AppStorage(SettingsKeys.voiceProcessingEnabled) private var voiceProcessingEnabled: Bool = true
    @AppStorage(SettingsKeys.noiseSuppressionEnabled) private var noiseSuppressionEnabled: Bool = true
    @AppStorage(SettingsKeys.vadEnabled) private var vadEnabled: Bool = true
    @AppStorage(SettingsKeys.enhancedDiarizationEnabled) private var enhancedDiarizationEnabled: Bool = false

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
