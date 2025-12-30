//
//  LocalLLMSettingsView.swift
//  Redactor
//
//  Purpose: Settings UI for local LLM PII review feature
//  Organization: 3 Big Things
//

import SwiftUI

struct LocalLLMSettingsView: View {

    @StateObject private var llmService = LocalLLMService.shared
    @AppStorage("localLLMEnabled") private var isEnabled: Bool = true
    @State private var isTestingConnection: Bool = false
    @State private var testResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Local PII Review")
                    .font(DesignSystem.Typography.heading)

                Text("Use a local AI model to scan redacted text for missed personal information.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Status Section
            statusSection

            Divider()

            // Model Selection (if available)
            if llmService.isAvailable {
                modelSelectionSection
                Divider()
            }

            // Setup Instructions (if not available)
            if !llmService.isAvailable {
                setupInstructionsSection
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

                // Connection status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(llmService.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(llmService.isAvailable ? "Connected" : "Not Connected")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(llmService.isAvailable ? .green : .red)
                }

                // Test connection button
                Button(action: testConnection) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Test")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingConnection)
            }

            // Test result message
            if let result = testResult {
                Text(result)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(result.contains("Success") ? .green : .orange)
                    .padding(.top, 4)
            }

            // Enable toggle
            Toggle("Enable local PII review", isOn: $isEnabled)
                .font(DesignSystem.Typography.body)
                .disabled(!llmService.isAvailable)
        }
    }

    // MARK: - Model Selection Section

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Model")
                .font(DesignSystem.Typography.subheading)

            Picker("Select Model", selection: $llmService.selectedModel) {
                ForEach(llmService.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 300)

            Text("Recommended: llama3.1:8b for best accuracy")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Setup Instructions Section

    private var setupInstructionsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Setup Required")
                .font(DesignSystem.Typography.subheading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("To enable local PII review, you need to install Ollama:")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(number: 1, text: "Download Ollama from ollama.com")
                    instructionRow(number: 2, text: "Install the application")
                    instructionRow(number: 3, text: "Open Terminal and run: ollama pull llama3.1:8b")
                    instructionRow(number: 4, text: "Keep Ollama running in the background")
                }
                .padding(.vertical, DesignSystem.Spacing.small)
            }

            HStack(spacing: DesignSystem.Spacing.medium) {
                Button(action: openOllamaWebsite) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Download Ollama")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(action: { Task { await llmService.checkAvailability() } }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
        .cornerRadius(DesignSystem.CornerRadius.medium)
    }

    // MARK: - Helper Views

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.primaryTeal)
                .frame(width: 20, alignment: .trailing)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }

    // MARK: - Actions

    private func testConnection() {
        isTestingConnection = true
        testResult = nil

        Task {
            await llmService.checkAvailability()

            await MainActor.run {
                isTestingConnection = false
                if llmService.isAvailable {
                    testResult = "Success! Found \(llmService.availableModels.count) model(s)"
                } else {
                    testResult = "Could not connect to Ollama"
                }
            }
        }
    }

    private func openOllamaWebsite() {
        if let url = URL(string: "https://ollama.com") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LocalLLMSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LocalLLMSettingsView()
            .frame(width: 500, height: 400)
    }
}
#endif
