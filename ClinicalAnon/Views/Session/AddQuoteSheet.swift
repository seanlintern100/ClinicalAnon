//
//  AddQuoteSheet.swift
//  ClinicalAnon
//
//  Purpose: Modal for manually adding a quote
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Add Quote Sheet

/// Modal for manually adding a quote to the parking lot
struct AddQuoteSheet: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @Environment(\.dismiss) private var dismiss

    @State private var quoteText: String = ""
    @State private var significance: String = ""

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
        .frame(width: 400, height: 340)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Quote")
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
            // Quote text field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Quote")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("Enter the quote...", text: $quoteText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .italic()
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(3...5)
            }

            // Significance field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Significance")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("Why is this quote significant?", text: $significance, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(2...3)
            }
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

            Button("Add Quote") {
                addQuote()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Actions

    private func addQuote() {
        let trimmedText = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSignificance = significance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        assistantService.addManualQuote(
            trimmedText,
            significance: trimmedSignificance.isEmpty ? "Manually added" : trimmedSignificance
        )
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct AddQuoteSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddQuoteSheet(
            assistantService: SessionManager.shared.assistantService
        )
    }
}
#endif
