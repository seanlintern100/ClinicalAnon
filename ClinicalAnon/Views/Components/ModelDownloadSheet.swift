//
//  ModelDownloadSheet.swift
//  Redactor
//
//  Purpose: Confirmation sheet for first-time model downloads
//  Organization: 3 Big Things
//

import SwiftUI

/// Reusable sheet for confirming and tracking model downloads
struct ModelDownloadSheet: View {
    let modelName: String
    let modelSize: String
    let isDownloading: Bool
    let progress: Double
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Download \(modelName)?")
                .font(.headline)

            Text("Size: ~\(modelSize)")
                .foregroundColor(.secondary)

            Text("This is a one-time download. The model will be cached locally for future use.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 16) {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.escape)
                    Button("Download", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                }
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - GLiNER Download Sheet (Observable)

/// GLiNER-specific download sheet that observes GLiNERService state
struct GLiNERDownloadSheet: View {
    @ObservedObject private var glinerService = GLiNERService.shared
    @Binding var isPresented: Bool
    let onDownloadComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Download \(DownloadableModel.gliner.displayName)?")
                .font(.headline)

            Text("Size: ~\(DownloadableModel.gliner.estimatedSize)")
                .foregroundColor(.secondary)

            Text("This is a one-time download. The model will be cached locally for future use.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if glinerService.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: glinerService.downloadProgress)
                        .progressViewStyle(.linear)
                    Text("Downloading... \(Int(glinerService.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let error = glinerService.lastError {
                VStack(spacing: 8) {
                    Text("Download failed")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        Button("Cancel") { isPresented = false }
                            .keyboardShortcut(.escape)
                        Button("Retry") { startDownload() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.escape)
                    Button("Download") { startDownload() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                }
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func startDownload() {
        Task {
            do {
                try await glinerService.downloadModel()
                await MainActor.run {
                    isPresented = false
                    onDownloadComplete()
                }
            } catch {
                print("GLiNER download failed: \(error)")
            }
        }
    }
}

// MARK: - Downloadable Model Info

/// Information about a downloadable AI model
enum DownloadableModel: String, CaseIterable {
    case llama = "llama"
    case gliner = "gliner"
    case xlmRoberta = "xlmRoberta"

    var displayName: String {
        switch self {
        case .llama:
            return "Llama 3.2 (3B)"
        case .gliner:
            return "GLiNER PII"
        case .xlmRoberta:
            return "XLM-RoBERTa NER"
        }
    }

    var estimatedSize: String {
        switch self {
        case .llama:
            return "2 GB"
        case .gliner:
            return "730 MB"
        case .xlmRoberta:
            return "1.1 GB"
        }
    }
}

#Preview {
    ModelDownloadSheet(
        modelName: "GLiNER PII",
        modelSize: "450 MB",
        isDownloading: false,
        progress: 0,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Downloading") {
    ModelDownloadSheet(
        modelName: "GLiNER PII",
        modelSize: "450 MB",
        isDownloading: true,
        progress: 0.45,
        onConfirm: {},
        onCancel: {}
    )
}
