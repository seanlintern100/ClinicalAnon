//
//  LocalLLMSettingsView.swift
//  Redactor
//
//  Purpose: Settings UI for local LLM PII review feature (MLX Swift)
//  Organization: 3 Big Things
//

import SwiftUI

struct LocalLLMSettingsView: View {

    @StateObject private var llmService = LocalLLMService.shared
    @AppStorage("localLLMEnabled") private var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Local PII Review")
                    .font(DesignSystem.Typography.heading)

                Text("Use a local AI model to scan redacted text for missed personal information. Models run entirely on your device.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Status Section
            statusSection

            Divider()

            // Model Selection
            if llmService.isAvailable {
                modelSelectionSection
                Divider()
            }

            // Download/Load Section
            if llmService.isAvailable {
                modelLoadSection
            } else {
                notSupportedSection
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            HStack {
                Text("Status")
                    .font(DesignSystem.Typography.subheading)

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(statusColor)
                }
            }

            // Enable toggle
            Toggle("Enable local PII review", isOn: $isEnabled)
                .font(DesignSystem.Typography.body)
                .disabled(!llmService.isAvailable)

            // Error message
            if let error = llmService.lastError {
                Text(error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var statusColor: Color {
        if !llmService.isAvailable {
            return .red
        } else if llmService.isModelLoaded {
            return .green
        } else {
            return .yellow
        }
    }

    private var statusText: String {
        if !llmService.isAvailable {
            return "Not Supported"
        } else if llmService.isModelLoaded {
            return "Model Loaded"
        } else if llmService.isDownloading {
            return "Downloading..."
        } else {
            return "Model Not Loaded"
        }
    }

    // MARK: - Model Selection Section

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Model")
                .font(DesignSystem.Typography.subheading)

            ForEach(LocalLLMService.availableModels) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: LocalLLMModelInfo) -> some View {
        let isSelected = llmService.selectedModelId == model.id

        return HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(model.size)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.background)
                        .cornerRadius(4)
                }

                Text(model.description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !llmService.isDownloading {
                llmService.selectedModelId = model.id
            }
        }
        .disabled(llmService.isDownloading)
    }

    // MARK: - Model Load Section

    private var modelLoadSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Model Status")
                .font(DesignSystem.Typography.subheading)

            if llmService.isDownloading {
                // Download progress
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text(llmService.downloadStatus)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    ProgressView(value: llmService.downloadProgress)
                        .progressViewStyle(.linear)

                    Text("\(Int(llmService.downloadProgress * 100))%")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.CornerRadius.medium)

            } else if llmService.isModelLoaded {
                // Model loaded
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Model Ready")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.green)
                        }

                        if let modelInfo = llmService.selectedModelInfo {
                            Text("\(modelInfo.name) is loaded and ready to use")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }

                    Spacer()

                    Button(action: { llmService.unloadModel() }) {
                        Text("Unload")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(DesignSystem.Spacing.medium)
                .background(Color.green.opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.medium)

            } else {
                // Model not loaded
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    if let modelInfo = llmService.selectedModelInfo {
                        Text("Selected: \(modelInfo.name)")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Text("The model will be downloaded automatically when you first use PII Review, or you can download it now.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }

                    Button(action: loadModel) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Download & Load Model")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.background)
                .cornerRadius(DesignSystem.CornerRadius.medium)
            }
        }
    }

    // MARK: - Not Supported Section

    private var notSupportedSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Apple Silicon Required")
                .font(DesignSystem.Typography.subheading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Local LLM requires an Apple Silicon Mac (M1, M2, M3, or M4)")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Text("This feature uses Metal Performance Shaders (MPS) which are only available on Apple Silicon.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(DesignSystem.Spacing.medium)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.medium)
        }
    }

    // MARK: - Actions

    private func loadModel() {
        Task {
            do {
                try await llmService.loadModel()
            } catch {
                // Error is already captured in llmService.lastError
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocalLLMSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LocalLLMSettingsView()
            .frame(width: 500, height: 500)
    }
}
#endif
