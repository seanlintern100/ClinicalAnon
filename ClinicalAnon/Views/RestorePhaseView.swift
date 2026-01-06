//
//  RestorePhaseView.swift
//  Redactor
//
//  Purpose: Third phase - final output with names restored
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Restore Phase View

/// Phase 3: Display final output with placeholder names restored to originals
struct RestorePhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar: Restored entities (left side)
            restoredEntitiesSidebar

            // Main content: Final output
            finalOutputPane
        }
        .sheet(isPresented: $viewModel.restoreState.showEditReplacementModal) {
            EditReplacementModal(viewModel: viewModel)
        }
    }

    // MARK: - Final Output Pane

    private var finalOutputPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Final Output")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if !viewModel.finalRestoredText.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.success)
                        Text("Restored")
                            .foregroundColor(DesignSystem.Colors.success)
                    }
                    .font(DesignSystem.Typography.caption)
                    .padding(.leading, DesignSystem.Spacing.small)
                }

                Spacer()

                if !viewModel.finalRestoredText.isEmpty {
                    Button(action: { viewModel.copyRestoredText() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: viewModel.justCopiedRestored ? "checkmark" : "doc.on.doc")
                                .frame(width: 14, height: 14)
                            Text(viewModel.justCopiedRestored ? "Copied!" : "Copy to Clipboard")
                                .frame(minWidth: 100)
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .animation(.easeInOut(duration: 0.2), value: viewModel.justCopiedRestored)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if let cachedRestored = viewModel.cachedRestoredAttributed, !viewModel.finalRestoredText.isEmpty {
                ScrollView {
                    TextContentCard(isSourcePanel: false, isProcessed: false) {
                        Text(cachedRestored)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.finalRestoredText.isEmpty {
                ScrollView {
                    TextContentCard(isSourcePanel: false, isProcessed: false) {
                        Text(viewModel.finalRestoredText)
                            .font(.system(size: 14))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state (should not normally appear)
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

                    Text("Restored text will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Bottom bar with Back button
            Divider().opacity(0.15)

            HStack {
                Button("← Back") {
                    viewModel.goToPreviousPhase()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button(action: { viewModel.clearAll() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Start New")
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(DesignSystem.Colors.panelNeutral)
                if !viewModel.finalRestoredText.isEmpty {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.success.opacity(0.05))
                }
            }
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Restored Entities Sidebar

    private var restoredEntitiesSidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Restored Entities")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Entity list (reversed: placeholder → original)
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(viewModel.restoredEntities) { entity in
                        RestoredEntityRow(
                            entity: entity,
                            overrideText: viewModel.restoreState.replacementOverrides[entity.replacementCode],
                            onEdit: { viewModel.restoreState.startEditingReplacement(entity) }
                        )
                    }
                }
                .padding(DesignSystem.Spacing.small)
            }

            // Summary
            Divider().opacity(0.15)

            HStack {
                Spacer()

                Text("\(viewModel.restoredEntities.count) \(viewModel.restoredEntities.count == 1 ? "entity" : "entities") restored")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .frame(width: 270)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Restored Entity Row

private struct RestoredEntityRow: View {

    let entity: Entity
    let overrideText: String?
    let onEdit: () -> Void

    /// Display text - uses override if available, otherwise original
    private var displayText: String {
        overrideText ?? entity.originalText
    }

    /// Whether this entity has a custom override
    private var hasOverride: Bool {
        overrideText != nil
    }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: hasOverride ? "pencil.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(hasOverride ? .orange : DesignSystem.Colors.success)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayText)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(hasOverride ? .orange : DesignSystem.Colors.textPrimary)

                    if let variant = entity.nameVariant {
                        Text(variant.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(entity.type.highlightColor.opacity(0.8))
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 4) {
                    Text("←")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(entity.replacementCode)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .font(.system(size: 11))
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(hasOverride ? Color.orange.opacity(0.1) : entity.type.highlightColor.opacity(0.1))
        )
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit Replacement", systemImage: "pencil")
            }
        }
    }
}

// MARK: - Edit Replacement Modal

struct EditReplacementModal: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header
            HStack {
                Text("Edit Replacement")
                    .font(DesignSystem.Typography.heading)

                Spacer()

                Button(action: { viewModel.restoreState.cancelReplacementEdit() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close dialog")
            }

            // Entity info
            if let entity = viewModel.restoreState.entityBeingEdited {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    HStack {
                        Text("Placeholder:")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(entity.replacementCode)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(entity.type.highlightColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(entity.type.highlightColor.opacity(0.15))
                            .cornerRadius(4)
                    }

                    HStack {
                        Text("Original:")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)

                        Text(entity.originalText)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(8)
            }

            // Edit field
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Replacement text:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                TextField("Enter replacement text", text: $viewModel.restoreState.editedReplacementText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
            }

            // Buttons
            HStack {
                Button("Cancel") {
                    viewModel.restoreState.cancelReplacementEdit()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Apply") {
                    viewModel.restoreState.applyReplacementEdit()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.restoreState.editedReplacementText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 400)
    }
}

// MARK: - Preview

#if DEBUG
struct RestorePhaseView_Previews: PreviewProvider {
    static var previews: some View {
        RestorePhaseView(viewModel: {
            let vm = WorkflowViewModel()
            vm.currentPhase = .restore
            vm.restoreState.finalRestoredText = "Sample restored text with names back in place."
            return vm
        }())
        .frame(width: 900, height: 600)
    }
}
#endif
