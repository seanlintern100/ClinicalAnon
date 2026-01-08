//
//  ModelDownloadSheet.swift
//  Redactor
//
//  Purpose: Confirmation sheet for first-time model downloads
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Download State Manager

/// Global state manager to track model download progress and prevent app quit during download
class DownloadStateManager: ObservableObject {
    static let shared = DownloadStateManager()

    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""

    private var activityToken: NSObjectProtocol?

    private init() {}

    /// Start tracking download - prevents system sleep
    func startDownload() {
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download..."

        // Prevent system sleep during download
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Downloading AI model"
        )
    }

    /// Update download progress
    func updateProgress(_ progress: Double, status: String) {
        downloadProgress = progress
        downloadStatus = status
    }

    /// End download tracking
    func endDownload() {
        isDownloading = false
        downloadProgress = 0
        downloadStatus = ""

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}

// MARK: - Deep Scan Download Sheet

/// Sheet shown before first-time Deep Scan model download
struct DeepScanDownloadSheet: View {
    @ObservedObject var downloadState = DownloadStateManager.shared
    let modelSize: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            // Title
            Text("Download AI Model for Deep Scan?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)

            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("Deep Scan uses a local AI model to find additional names and identifiers that standard detection might miss.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(DesignSystem.Colors.primaryTeal)
                    Text("**This is optional** — standard scanning already catches most PII. Deep Scan is useful for extra thoroughness.")
                        .font(.system(size: 12))
                }
                .padding(10)
                .background(DesignSystem.Colors.primaryTeal.opacity(0.1))
                .cornerRadius(8)

                // Details grid
                VStack(alignment: .leading, spacing: 6) {
                    DetailRow(label: "Download size:", value: "~\(modelSize)")
                    DetailRow(label: "Download time:", value: "5-15 minutes (depending on connection)")
                    DetailRow(label: "First scan:", value: "May take 1-2 minutes while model loads")
                    DetailRow(label: "Future scans:", value: "Much faster (model stays cached)")
                }
                .font(.system(size: 12))
                .padding(.top, 4)

                Text("You can delete the model later in Settings to free up space.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Progress or Buttons
            if downloadState.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: downloadState.downloadProgress)
                        .progressViewStyle(.linear)

                    Text(downloadState.downloadStatus)
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Text("Please don't quit the app during download.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.top, 8)
            } else {
                HStack(spacing: 16) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape)

                    Button("Download & Scan", action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.primaryTeal)
                        .keyboardShortcut(.return)
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(downloadState.isDownloading)
    }
}

/// Helper view for detail rows
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

// MARK: - Legacy Model Download Sheet (kept for compatibility)

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

// MARK: - Previews

#Preview("Deep Scan Download") {
    DeepScanDownloadSheet(
        modelSize: "2 GB",
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Deep Scan Downloading") {
    let state = DownloadStateManager.shared
    state.isDownloading = true
    state.downloadProgress = 0.45
    state.downloadStatus = "Downloading model files... 45%"

    return DeepScanDownloadSheet(
        downloadState: state,
        modelSize: "2 GB",
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("Legacy Sheet") {
    ModelDownloadSheet(
        modelName: "XLM-RoBERTa NER",
        modelSize: "1.1 GB",
        isDownloading: false,
        progress: 0,
        onConfirm: {},
        onCancel: {}
    )
}
