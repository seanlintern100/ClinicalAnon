//
//  AISettingsView.swift
//  Redactor
//
//  Purpose: Settings view for AWS Bedrock credentials and model selection
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - AI Settings View

/// Settings tab for configuring AWS Bedrock credentials
struct AISettingsView: View {

    // MARK: - Properties

    @StateObject private var credentialsManager = AWSCredentialsManager.shared

    @State private var accessKeyId: String = ""
    @State private var secretAccessKey: String = ""
    @State private var selectedRegion: String = "us-east-1"
    @State private var selectedModel: String = ""

    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?

    // MARK: - Body

    var body: some View {
        Form {
            // AWS Credentials Section
            Section {
                TextField("Access Key ID", text: $accessKeyId)
                    .textFieldStyle(.roundedBorder)

                SecureField("Secret Access Key", text: $secretAccessKey)
                    .textFieldStyle(.roundedBorder)

                Picker("Region", selection: $selectedRegion) {
                    ForEach(AWSCredentialsManager.availableRegions, id: \.id) { region in
                        Text(region.name).tag(region.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("AWS Credentials")
            } footer: {
                Text("Your credentials are stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Model Selection Section
            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(AWSCredentialsManager.availableModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("AI Model")
            } footer: {
                Text("Select the Claude model to use for text processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Actions Section
            Section {
                HStack {
                    Button("Save Credentials") {
                        saveCredentials()
                    }
                    .disabled(accessKeyId.isEmpty || secretAccessKey.isEmpty)

                    Spacer()

                    Button(action: testConnection) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(accessKeyId.isEmpty || secretAccessKey.isEmpty || isTesting)
                }

                // Test result
                if let result = testResult {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(result.success ? .green : .red)
                    }
                }
            }

            // Clear Credentials Section
            Section {
                Button("Clear All Credentials", role: .destructive) {
                    clearCredentials()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 400)
        .onAppear {
            loadCredentials()
        }
    }

    // MARK: - Private Methods

    private func loadCredentials() {
        accessKeyId = credentialsManager.accessKeyId ?? ""
        secretAccessKey = credentialsManager.secretAccessKey ?? ""
        selectedRegion = credentialsManager.region
        selectedModel = credentialsManager.selectedModel
    }

    private func saveCredentials() {
        credentialsManager.saveCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: selectedRegion
        )
        credentialsManager.selectedModel = selectedModel
        testResult = TestResult(success: true, message: "Credentials saved successfully")
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                // Save current values first
                credentialsManager.saveCredentials(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    region: selectedRegion
                )

                // Create credentials struct for testing
                let credentials = AWSCredentials(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    region: selectedRegion
                )

                let bedrockService = BedrockService()
                try await bedrockService.configure(with: credentials)
                try await bedrockService.testConnection()

                await MainActor.run {
                    testResult = TestResult(success: true, message: "Connection successful!")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = TestResult(success: false, message: error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func clearCredentials() {
        credentialsManager.clearCredentials()
        accessKeyId = ""
        secretAccessKey = ""
        selectedRegion = "us-east-1"
        selectedModel = AWSCredentialsManager.defaultModel
        testResult = nil
    }

}

// MARK: - Test Result

private struct TestResult {
    let success: Bool
    let message: String
}

// MARK: - Settings Container View

/// Container for all settings tabs
struct SettingsContainerView: View {

    var body: some View {
        TabView {
            AISettingsView()
                .tabItem {
                    Label("AI Settings", systemImage: "brain")
                }

            ExclusionSettingsView()
                .tabItem {
                    Label("Exclusions", systemImage: "eye.slash")
                }
        }
        .frame(width: 500, height: 450)
    }
}

// MARK: - Preview

#if DEBUG
struct AISettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AISettingsView()
    }
}

struct SettingsContainerView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsContainerView()
    }
}
#endif
