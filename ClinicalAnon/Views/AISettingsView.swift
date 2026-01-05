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

            LocalLLMSettingsView()
                .tabItem {
                    Label("Local Review", systemImage: "desktopcomputer")
                }

            DetectionSettingsView()
                .tabItem {
                    Label("Detection", systemImage: "magnifyingglass")
                }

            ExclusionSettingsView()
                .tabItem {
                    Label("Exclusions", systemImage: "eye.slash")
                }
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - Detection Settings View

struct DetectionSettingsView: View {
    @AppStorage("redactAllNumbers") private var redactAllNumbers: Bool = true
    @AppStorage(SettingsKeys.dateRedactionLevel) private var dateRedactionLevel: String = "keepYear"

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $redactAllNumbers) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Redact all numbers")
                            .font(.body)
                        Text("Catch any numeric values not detected as dates, phone numbers, or IDs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Number Detection")
            } footer: {
                Text("When enabled, all numbers (amounts, reference numbers, years, etc.) will be flagged for review and redaction.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Picker("Date Redaction Level", selection: $dateRedactionLevel) {
                    Text("Keep Year (e.g., [DATE_A] 2024)").tag("keepYear")
                    Text("Full Redaction (e.g., [DATE_A])").tag("full")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Date Handling")
            } footer: {
                Text("Keep Year preserves temporal context for AI processing while hiding specific day/month.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Dates are detected separately (15/03/2024)", systemImage: "calendar")
                    Label("Phone numbers are detected separately (021-555-1234)", systemImage: "phone")
                    Label("Medical IDs are detected separately (NHI, ACC)", systemImage: "number.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Specific Detectors")
            }
        }
        .formStyle(.grouped)
        .padding()
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
