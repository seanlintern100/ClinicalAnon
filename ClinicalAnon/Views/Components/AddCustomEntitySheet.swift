//
//  AddCustomEntitySheet.swift
//  Redactor
//
//  Purpose: Sheet for adding custom redaction entities.
//           Shared between full app and Lite.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Add Custom Entity Sheet

struct AddCustomEntitySheet: View {

    let prefilledText: String?
    let onAdd: (String, EntityType) -> Void

    @State private var text: String = ""
    @State private var selectedType: EntityType = .personClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("Add Custom Redaction")
                .font(DesignSystem.Typography.heading)

            TextField("Text to redact", text: $text)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    if let prefilled = prefilledText {
                        text = prefilled
                    }
                }

            Picker("Entity Type", selection: $selectedType) {
                ForEach(EntityType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Add") {
                    onAdd(text, selectedType)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 350)
    }
}
