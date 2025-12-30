//
//  AISettingsView.swift
//  Redactor
//
//  Purpose: Settings views for AI model selection and exclusions
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Settings Container View

/// Container for all settings tabs
struct SettingsContainerView: View {

    var body: some View {
        TabView {
            AIModelSettingsView()
                .tabItem {
                    Label("AI Model", systemImage: "cpu")
                }

            ExclusionSettingsView()
                .tabItem {
                    Label("Exclusions", systemImage: "eye.slash")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - AI Model Settings View

struct AIModelSettingsView: View {
    @StateObject private var credentialsManager = AWSCredentialsManager.shared

    var body: some View {
        Form {
            // Status Section
            Section {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Service Connected")
                            .font(.headline)
                        Text("Using secure cloud proxy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text("Status")
            }

            // Model Selection Section
            Section {
                Picker("Claude Model", selection: $credentialsManager.selectedModel) {
                    ForEach(AWSCredentialsManager.availableModels, id: \.id) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .onChange(of: credentialsManager.selectedModel) { newValue in
                    credentialsManager.saveModel(newValue)
                }
            } header: {
                Text("AI Model")
            } footer: {
                Text("Sonnet 4 offers the best balance of quality and speed. Haiku is faster but less capable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No AWS credentials needed", systemImage: "lock.shield")
                    Label("All requests go through secure proxy", systemImage: "network")
                    Label("Data encrypted in transit", systemImage: "lock")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Security")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsContainerView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsContainerView()
    }
}

struct AIModelSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AIModelSettingsView()
            .frame(width: 500, height: 350)
    }
}
#endif
