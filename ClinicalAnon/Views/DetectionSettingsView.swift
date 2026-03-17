//
//  DetectionSettingsView.swift
//  ClinicalAnon
//
//  Purpose: Detection settings shared between full app and Lite.
//  Organization: 3 Big Things
//

import SwiftUI

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
