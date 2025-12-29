//
//  ImprovePhaseView.swift
//  Redactor
//
//  Purpose: Second phase - AI polish or generate
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Improve Phase View

/// Phase 2: Send redacted text to AI for polishing or report generation
struct ImprovePhaseView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector and template chips
            modeSelector

            Divider().opacity(0.3)

            // Two-pane content: Redacted Input | AI Output
            HStack(spacing: 0) {
                redactedInputPane
                aiOutputPane
            }
        }
        .sheet(isPresented: $viewModel.showCustomPromptSheet) {
            CustomPromptSheet(viewModel: viewModel)
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Mode toggle: Polish vs Generate
            HStack(spacing: DesignSystem.Spacing.medium) {
                ForEach(AIMode.allCases, id: \.self) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: viewModel.aiMode == mode,
                        onSelect: { viewModel.aiMode = mode }
                    )
                }

                Spacer()
            }

            // Template chips (only visible in Generate mode)
            if viewModel.aiMode == .generate {
                HStack(spacing: DesignSystem.Spacing.small) {
                    ForEach(ReportTemplate.quickSelectTemplates, id: \.self) { template in
                        TemplateChip(
                            template: template,
                            isSelected: viewModel.selectedTemplate == template,
                            onSelect: { viewModel.selectedTemplate = template }
                        )
                    }

                    // Custom chip
                    TemplateChip(
                        template: .custom,
                        isSelected: viewModel.selectedTemplate == .custom,
                        onSelect: { viewModel.openCustomPromptSheet() }
                    )

                    Spacer()
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.surface)
    }

    // MARK: - Redacted Input Pane

    private var redactedInputPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Redacted Input")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Spacer()

                Text("Read-only")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            ScrollView {
                if let cachedRedacted = viewModel.cachedRedactedAttributed {
                    Text(cachedRedacted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                } else {
                    Text(viewModel.displayedRedactedText)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Process button
            Divider().opacity(0.15)

            HStack {
                Button("← Back") {
                    viewModel.goToPreviousPhase()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button(action: { viewModel.processWithAI() }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: viewModel.aiMode.icon)
                        Text(viewModel.aiMode == .polish ? "Polish Text" : "Generate \(viewModel.selectedTemplate.shortName)")
                    }
                    .font(DesignSystem.Typography.body)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.displayedRedactedText.isEmpty || viewModel.isAIProcessing)
            }
            .padding(DesignSystem.Spacing.medium)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - AI Output Pane

    private var aiOutputPane: some View {
        VStack(spacing: 0) {
            // Header with Redo button
            HStack {
                Text("AI Output")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if viewModel.isAIProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, DesignSystem.Spacing.xs)
                }

                Spacer()

                if !viewModel.aiOutput.isEmpty && !viewModel.isAIProcessing {
                    Button(action: { viewModel.regenerateAIOutput() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "arrow.clockwise")
                            Text("Redo")
                        }
                        .font(DesignSystem.Typography.caption)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if viewModel.isAIProcessing {
                    Button("Cancel") {
                        viewModel.cancelAIRequest()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(height: 52)
            .padding(.horizontal, DesignSystem.Spacing.medium)

            Divider().opacity(0.15)

            // Content
            if viewModel.isAIProcessing && viewModel.aiOutput.isEmpty {
                // Loading skeleton
                SkeletonTextView()
            } else if let error = viewModel.aiError {
                // Error state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.error)

                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Try Again") {
                        viewModel.dismissError()
                        viewModel.processWithAI()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.aiOutput.isEmpty {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.medium) {
                    Spacer()

                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))

                    Text("AI output will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)

                    Text("Select a mode and click \"\(viewModel.aiMode == .polish ? "Polish Text" : "Generate")\"")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // AI output content
                ScrollView {
                    Text(viewModel.aiOutput)
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DesignSystem.Spacing.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Continue button
            if !viewModel.aiOutput.isEmpty && !viewModel.isAIProcessing {
                Divider().opacity(0.15)

                HStack {
                    Spacer()

                    Button(action: { viewModel.continueToNextPhase() }) {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(DesignSystem.Typography.body)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(DesignSystem.Spacing.medium)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.surface)
        )
        .cornerRadius(DesignSystem.CornerRadius.medium)
        .padding(6)
        .frame(minWidth: 350, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mode Button

private struct ModeButton: View {

    let mode: AIMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)

                    Text(mode.description)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(isSelected ? DesignSystem.Colors.primaryTeal.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textPrimary)
    }
}

// MARK: - Template Chip

private struct TemplateChip: View {

    let template: ReportTemplate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(template.displayName)
                .font(DesignSystem.Typography.caption)
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .background(
                    Capsule()
                        .fill(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
    }
}

// MARK: - Skeleton Text View

private struct SkeletonTextView: View {

    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(DesignSystem.Colors.textSecondary.opacity(0.15))
                    .frame(height: 16)
                    .frame(maxWidth: index == 7 ? 200 : .infinity)
            }

            Spacer()
        }
        .padding(DesignSystem.Spacing.medium)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Custom Prompt Sheet

struct CustomPromptSheet: View {

    @ObservedObject var viewModel: WorkflowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("Custom Instructions")
                .font(DesignSystem.Typography.heading)

            Text("Describe what kind of report or output you'd like the AI to generate:")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            TextEditor(text: $viewModel.customPrompt)
                .font(.system(size: 14))
                .frame(height: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .stroke(DesignSystem.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Generate") {
                    viewModel.generateWithCustomPrompt()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.large)
        .frame(width: 450)
    }
}

// MARK: - Preview

#if DEBUG
struct ImprovePhaseView_Previews: PreviewProvider {
    static var previews: some View {
        ImprovePhaseView(viewModel: {
            let vm = WorkflowViewModel()
            vm.currentPhase = .improve
            return vm
        }())
        .frame(width: 900, height: 600)
    }
}
#endif
