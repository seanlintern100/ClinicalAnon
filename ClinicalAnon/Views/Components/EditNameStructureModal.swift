//
//  EditNameStructureModal.swift
//  Redactor
//
//  Purpose: Modal for editing name structure (first/middle/last/title).
//           Shared between full app and Lite.
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Edit Name Structure Modal

struct EditNameStructureModal: View {

    let entity: Entity
    let onSave: (_ firstName: String, _ middleName: String?, _ lastName: String?, _ title: String?) -> Void
    let onCancel: () -> Void
    let getPersonForCode: (String) -> RedactedPerson?

    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var middleName: String = ""
    @State private var lastName: String = ""
    @State private var title: String = ""

    private let titleOptions = ["", "Mr", "Mrs", "Ms", "Miss", "Dr", "Prof", "Rev"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Name Structure")
                    .font(DesignSystem.Typography.heading)
                Text(entity.baseReplacementCode)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Divider()

            // Detected text reference
            HStack {
                Text("Detected:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text(entity.originalText)
                    .font(DesignSystem.Typography.caption)
                    .italic()
            }

            // Editable fields
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                LabeledContent("Title") {
                    Picker("", selection: $title) {
                        ForEach(titleOptions, id: \.self) { opt in
                            Text(opt.isEmpty ? "None" : opt).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                LabeledContent("First Name") {
                    TextField("First", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                LabeledContent("Middle Name") {
                    TextField("Middle (optional)", text: $middleName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                LabeledContent("Last Name") {
                    TextField("Last", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            // Preview of full name
            if !firstName.isEmpty || !lastName.isEmpty {
                HStack {
                    Text("Full name:")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(buildFullNamePreview())
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                }
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Save") {
                    onSave(
                        firstName,
                        middleName.isEmpty ? nil : middleName,
                        lastName.isEmpty ? nil : lastName,
                        title.isEmpty ? nil : title
                    )
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 350)
        .onAppear {
            loadExistingStructure()
        }
    }

    private func loadExistingStructure() {
        // Try to load existing RedactedPerson if available
        if let person = getPersonForCode(entity.replacementCode) {
            firstName = person.first
            middleName = person.middle ?? ""
            lastName = person.last
            title = person.detectedTitle ?? ""
        } else {
            // Parse from the entity's original text as default
            parseFromOriginalText()
        }
    }

    private func parseFromOriginalText() {
        let text = entity.originalText

        // Strip title if present
        let titles = ["Mr", "Mrs", "Ms", "Miss", "Dr", "Prof", "Rev", "Mr.", "Mrs.", "Ms.", "Dr.", "Prof."]
        var parts = text.components(separatedBy: " ").filter { !$0.isEmpty }

        if let firstPart = parts.first, titles.contains(where: { firstPart.lowercased() == $0.lowercased() }) {
            title = firstPart.replacingOccurrences(of: ".", with: "")
            parts.removeFirst()
        }

        // Assign parts to name fields
        if parts.count >= 1 {
            firstName = parts[0]
        }
        if parts.count >= 2 {
            lastName = parts[parts.count - 1]
        }
        if parts.count >= 3 {
            middleName = parts[1..<parts.count - 1].joined(separator: " ")
        }
    }

    private func buildFullNamePreview() -> String {
        var parts: [String] = []
        if !title.isEmpty { parts.append(title) }
        if !firstName.isEmpty { parts.append(firstName) }
        if !middleName.isEmpty { parts.append(middleName) }
        if !lastName.isEmpty { parts.append(lastName) }
        return parts.joined(separator: " ")
    }
}
