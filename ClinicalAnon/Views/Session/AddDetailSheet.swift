//
//  AddDetailSheet.swift
//  ClinicalAnon
//
//  Purpose: Modal for manually adding a client detail
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Add Detail Sheet

/// Modal for manually adding a detail to the parking lot
struct AddDetailSheet: View {

    // MARK: - Properties

    @ObservedObject var assistantService: SessionAssistantService
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var category: DetailCategory = .fact

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
        .frame(width: 400, height: 320)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Detail")
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
            // Content field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Content")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextField("Enter detail...", text: $content, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .padding(DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(3...5)
            }

            // Category picker
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Category")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Spacing.small) {
                    ForEach(DetailCategory.allCases) { cat in
                        categoryButton(cat)
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(maxHeight: .infinity)
    }

    private func categoryButton(_ cat: DetailCategory) -> some View {
        Button {
            category = cat
        } label: {
            VStack(spacing: 4) {
                Image(systemName: cat.icon)
                    .font(.body)
                Text(cat.displayName)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                category == cat
                    ? DesignSystem.Colors.primaryTeal.opacity(0.1)
                    : DesignSystem.Colors.surface
            )
            .foregroundStyle(
                category == cat
                    ? DesignSystem.Colors.primaryTeal
                    : DesignSystem.Colors.textSecondary
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        category == cat
                            ? DesignSystem.Colors.primaryTeal
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            Button("Add Detail") {
                addDetail()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(DesignSystem.Spacing.medium)
    }

    // MARK: - Actions

    private func addDetail() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        assistantService.addManualDetail(trimmed, category: category)
        dismiss()
    }
}

// MARK: - Preview

#if DEBUG
struct AddDetailSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddDetailSheet(
            assistantService: SessionManager.shared.assistantService
        )
    }
}
#endif
