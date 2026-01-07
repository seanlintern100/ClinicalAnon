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

// MARK: - Downloadable Model Info

/// Information about a downloadable AI model
enum DownloadableModel: String, CaseIterable {
    case llama = "llama"
    case xlmRoberta = "xlmRoberta"

    var displayName: String {
        switch self {
        case .llama:
            return "Llama 3.2 (3B)"
        case .xlmRoberta:
            return "XLM-RoBERTa NER"
        }
    }

    var estimatedSize: String {
        switch self {
        case .llama:
            return "2 GB"
        case .xlmRoberta:
            return "1.1 GB"
        }
    }
}

#Preview {
    ModelDownloadSheet(
        modelName: "XLM-RoBERTa NER",
        modelSize: "1.1 GB",
        isDownloading: false,
        progress: 0,
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Downloading") {
    ModelDownloadSheet(
        modelName: "XLM-RoBERTa NER",
        modelSize: "1.1 GB",
        isDownloading: true,
        progress: 0.45,
        onConfirm: {},
        onCancel: {}
    )
}
