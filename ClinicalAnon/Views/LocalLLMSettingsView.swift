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

                if let error = llmService.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Use a local AI model to scan redacted text for missed personal information. Models run entirely on your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Model Selection
            if llmService.isAvailable {
                Section {
                    ForEach(LocalLLMService.availableModels) { model in
                        modelRow(model)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Select which model to use for PII review. Larger models are more accurate but use more memory.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Model Status Section
            if llmService.isAvailable {
                Section {
                    modelStatusContent
                } header: {
                    Text("Model Status")
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Local LLM requires Apple Silicon (M1/M2/M3/M4)")
                            .font(.body)
                    }
                } header: {
                    Text("Requirements")
                } footer: {
                    Text("This feature uses Metal Performance Shaders which are only available on Apple Silicon Macs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        if !llmService.isAvailable {
            return .red
        } else if llmService.isModelLoaded {
            return .green
        } else if llmService.isModelCached {
            return .blue
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
        } else if llmService.isModelCached {
            return "Downloaded (Not Loaded)"
        } else {
            return "Not Downloaded"
        }
    }

    // MARK: - Model Row

    private func modelRow(_ model: LocalLLMModelInfo) -> some View {
        let isSelected = llmService.selectedModelId == model.id

        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(model.name)
                        .font(.body)
                    Text(model.size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !llmService.isDownloading {
                llmService.selectedModelId = model.id
            }
        }
    }

    // MARK: - Model Status Content

    @ViewBuilder
    private var modelStatusContent: some View {
        if llmService.isDownloading {
            VStack(alignment: .leading, spacing: 8) {
                Text(llmService.downloadStatus)
                    .font(.body)
                ProgressView(value: llmService.downloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(llmService.downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if llmService.isModelLoaded {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Model Ready")
                            .font(.body)
                    }
                    if let modelInfo = llmService.selectedModelInfo {
                        Text("\(modelInfo.name) is loaded and ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Unload") {
                    llmService.unloadModel()
                }
            }
        } else if llmService.isModelCached {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Model Downloaded")
                        .font(.body)
                }
                if let modelInfo = llmService.selectedModelInfo {
                    Text("\(modelInfo.name) is ready to load")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button("Load Model") {
                        loadModel()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete") {
                        llmService.deleteModel()
                    }
                    .foregroundColor(.red)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let modelInfo = llmService.selectedModelInfo {
                    Text("Selected: \(modelInfo.name)")
                        .font(.body)
                    Text("The model will download automatically when first used, or you can download now.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button("Download & Load Model") {
                    loadModel()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func loadModel() {
        Task {
            do {
                try await llmService.loadModel()
            } catch {
                // Error captured in llmService.lastError
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocalLLMSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LocalLLMSettingsView()
            .frame(width: 500, height: 450)
    }
}
#endif
