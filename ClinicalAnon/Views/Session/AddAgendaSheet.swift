//
//  AddAgendaSheet.swift
//  ClinicalAnon
//
//  Purpose: Modal for manually adding an agenda item
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Add Agenda Sheet

/// Modal for manually adding an agenda item to the parking lot
struct AddAgendaSheet: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @Environment(\.dismiss) private var dismiss

    @State private var topic: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Form
            form

            Divider()

            // Actions
            actions
        }
        .frame(width: 400, height: 220)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Agenda Item")
                .font(DesignSystem.Typography.subheading)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Topic field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Topic")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("What should be discussed?", text: $topic, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(2...3)
            }

            Text("New agenda items start with 'Not Started' status")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button("Add to Agenda") {
                addAgendaItem()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Actions

    private func addAgendaItem() {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        assistantService.addManualAgendaItem(trimmed)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct AddAgendaSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddAgendaSheet(
            assistantService: SessionManager.shared.assistantService
        )
    }
}
#endif
