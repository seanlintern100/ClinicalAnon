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
            // Main content: Final output
            finalOutputPane

            // Sidebar: Restored entities
            restoredEntitiesSidebar
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
                    Text(cachedRestored)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.finalRestoredText.isEmpty {
                ScrollView {
                    Text(viewModel.finalRestoredText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
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
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(
                    viewModel.finalRestoredText.isEmpty
                        ? DesignSystem.Colors.surface
                        : DesignSystem.Colors.success.opacity(0.05)
                )
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
                    ForEach(viewModel.activeEntities) { entity in
                        RestoredEntityRow(entity: entity)
                    }
                }
                .padding(DesignSystem.Spacing.small)
            }

            // Summary
            Divider().opacity(0.15)

            HStack {
                Spacer()

                Text("\(viewModel.activeEntities.count) \(viewModel.activeEntities.count == 1 ? "entity" : "entities") restored")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Spacer()
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .frame(width: 200)
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Restored Entity Row

private struct RestoredEntityRow: View {

    let entity: Entity

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.Colors.success)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.replacementCode)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                HStack(spacing: 4) {
                    Text("→")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    Text(entity.originalText)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .font(.system(size: 11))
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(entity.type.highlightColor.opacity(0.1))
        )
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
