//
//  FirstTimeSetupView.swift
//  Redactor
//
//  Purpose: One-time setup modal for export folder and transcription model
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - First Time Setup View

struct FirstTimeSetupView: View {

    @ObservedObject var coworkExport: CoworkExportService
    @ObservedObject var transcriptionService: TranscriptionService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "gear.badge")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignSystem.Colors.primaryTeal)

                Text("Recording Setup")
                    .font(DesignSystem.Typography.heading)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("These settings are saved and only need to be configured once. You can change them later in Settings > Recording.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {

                // MARK: - Export Folder
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Label("Export Folder", systemImage: "folder")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("Choose where session transcripts are saved. Point this at the folder Claude Cowork monitors.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if let folderURL = coworkExport.exportRootFolderURL {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(folderURL.path)
                                .font(DesignSystem.Typography.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Button(coworkExport.hasRootFolder ? "Change Folder..." : "Choose Folder...") {
                        selectExportFolder()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // MARK: - Transcription Model
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Label("Transcription Model", systemImage: "waveform")
                        .font(DesignSystem.Typography.subheading)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("A speech-to-text model is needed for transcription. The \"small\" model is recommended (500 MB download).")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if transcriptionService.isModelLoaded {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Model ready: \(transcriptionService.loadedModelSize?.rawValue ?? "loaded")")
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
                    }
                }
            }
            .padding()

            Spacer()

            Divider()

            // Done button
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canDismiss)
            }
            .padding()
        }
        .frame(width: 440, height: 480)
    }

    private var canDismiss: Bool {
        coworkExport.hasRootFolder
    }

    private func selectExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Cowork Export Folder"
        panel.message = "Choose the folder that Claude Cowork monitors"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            coworkExport.setRootFolder(url)
        }
    }
}
