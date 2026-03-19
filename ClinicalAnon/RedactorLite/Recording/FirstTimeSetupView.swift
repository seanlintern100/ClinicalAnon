//
//  FirstTimeSetupView.swift
//  Redactor
//
//  Purpose: One-time setup modal for transcription model download
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - First Time Setup View

struct FirstTimeSetupView: View {

    @ObservedObject var exportService: SessionExportService
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

                Text("A speech-to-text model is needed before recording. You can change the model later in Settings > Recording.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {

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
        .frame(width: 440, height: 400)
    }

    private var canDismiss: Bool {
        transcriptionService.isModelLoaded || transcriptionService.isModelCached(size: transcriptionService.selectedModelSize)
    }
}
