//
//  RecordingSettingsView.swift
//  Redactor Lite
//
//  Purpose: Recording settings — model picker, echo cancellation, export folder
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Recording Settings View

struct RecordingSettingsView: View {

    @ObservedObject var coworkExport: CoworkExportService
    @ObservedObject private var transcriptionService = TranscriptionService.shared
    @ObservedObject private var sessionManager = SessionManager.shared

    @AppStorage(SettingsKeys.voiceProcessingEnabled) private var echoCancellation = true
    @AppStorage(SettingsKeys.vadEnabled) private var vadEnabled = true
    @AppStorage(SettingsKeys.vadSensitivity) private var vadSensitivity = 0.5
    @AppStorage(SettingsKeys.noiseSuppressionEnabled) private var noiseSuppression = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Recording Settings")
                    .font(DesignSystem.Typography.heading)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {

                    // MARK: - Transcription Model
                    settingsSection("Transcription Model") {
                        Picker("Model Size", selection: $transcriptionService.selectedModelSize) {
                            ForEach(WhisperModelSize.allCases, id: \.self) { size in
                                Text("\(size.rawValue) (\(size.sizeDescription))").tag(size)
                            }
                        }
                        .pickerStyle(.menu)

                        if transcriptionService.isModelLoaded {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Model loaded: \(transcriptionService.loadedModelSize?.rawValue ?? "unknown")")
                                    .font(DesignSystem.Typography.caption)
                            }
                        }

                        if transcriptionService.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: max(0, transcriptionService.downloadProgress))
                                Text(transcriptionService.downloadStatus)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }

                        HStack {
                            Button("Download Selected Model") {
                                Task {
                                    try? await transcriptionService.downloadModel(size: transcriptionService.selectedModelSize)
                                }
                            }
                            .disabled(transcriptionService.isDownloading)

                            if transcriptionService.isModelLoaded {
                                Button("Unload Model") {
                                    transcriptionService.unloadModel()
                                }
                            }
                        }
                    }

                    // MARK: - Audio Settings
                    settingsSection("Audio") {
                        Toggle("Echo Cancellation", isOn: $echoCancellation)
                            .help("Removes echo when recording video calls")

                        Toggle("Noise Suppression", isOn: $noiseSuppression)

                        Toggle("Voice Activity Detection", isOn: $vadEnabled)

                        if vadEnabled {
                            HStack {
                                Text("VAD Sensitivity")
                                Slider(value: $vadSensitivity, in: 0...1)
                                Text(String(format: "%.0f%%", vadSensitivity * 100))
                                    .frame(width: 40)
                            }
                        }
                    }

                    // MARK: - Microphone
                    settingsSection("Microphone") {
                        let devices = sessionManager.availableInputDevices
                        if devices.isEmpty {
                            Text("No input devices found")
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        } else {
                            ForEach(devices, id: \.id) { device in
                                HStack {
                                    Image(systemName: device.id == sessionManager.selectedInputDevice?.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(device.id == sessionManager.selectedInputDevice?.id ? .blue : DesignSystem.Colors.textSecondary)
                                    Text(device.name)
                                        .font(DesignSystem.Typography.body)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    sessionManager.selectInputDevice(device)
                                }
                            }
                        }

                        Button("Refresh Devices") {
                            sessionManager.refreshInputDevices()
                        }
                        .controlSize(.small)
                    }

                    // MARK: - Export Folder
                    settingsSection("Cowork Export") {
                        if let folderURL = coworkExport.exportRootFolderURL {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(folderURL.path)
                                    .font(DesignSystem.Typography.caption)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        } else {
                            Text("No export folder selected")
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }

                        Button("Choose Folder...") {
                            selectExportFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding()
            }
        }
        .frame(width: 450, height: 550)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text(title)
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            content()
        }
    }

    private func selectExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Cowork Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            coworkExport.setRootFolder(url)
        }
    }
}
