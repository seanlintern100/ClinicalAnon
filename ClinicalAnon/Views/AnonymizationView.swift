//
//  AnonymizationView.swift
//  ClinicalAnon
//
//  Purpose: Main anonymization interface
//  Organization: 3 Big Things
//

import SwiftUI
import AppKit

// MARK: - Anonymization View

/// Main view for clinical text anonymization
struct AnonymizationView: View {

    // MARK: - Properties

    @StateObject private var viewModel: AnonymizationViewModel

    // MARK: - Initialization

    init(ollamaService: OllamaServiceProtocol, setupManager: SetupManager) {
        let engine = AnonymizationEngine(ollamaService: ollamaService)
        _viewModel = StateObject(wrappedValue: AnonymizationViewModel(engine: engine, setupManager: setupManager))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()

            Divider()

            // Main content
            HSplitView {
                // Left: Input and actions
                VStack(spacing: DesignSystem.Spacing.medium) {
                    TextEditorWithActionsView(
                        title: "Original Text",
                        text: $viewModel.inputText,
                        placeholder: "Enter clinical text to anonymize...",
                        isEditable: true,
                        onCopy: { viewModel.copyInputText() },
                        onClear: { viewModel.clearInputText() }
                    )

                    ActionBar(
                        onAnalyze: { Task { await viewModel.analyze() } },
                        onClearAll: { viewModel.clearAll() },
                        isAnalyzing: viewModel.isProcessing,
                        hasText: !viewModel.inputText.isEmpty
                    )
                }
                .padding(DesignSystem.Spacing.medium)
                .frame(minWidth: 400)

                Divider()

                // Right: Output and entities
                VStack(spacing: DesignSystem.Spacing.medium) {
                    if let result = viewModel.result {
                        // Anonymized text with highlighting
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            HStack {
                                Text("Anonymized Text")
                                    .font(DesignSystem.Typography.subheading)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)

                                Spacer()

                                Button(action: { viewModel.copyAnonymizedText() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy")
                                    }
                                    .font(DesignSystem.Typography.caption)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }

                            HighlightedTextWithLegendView(
                                text: result.anonymizedText,
                                entities: result.entities,
                                onEntityClick: nil
                            )
                        }

                        // Entity list
                        EntityListView(entities: result.entities) { entity in
                            print("Entity tapped: \(entity.originalText)")
                        }

                        // Result summary
                        ResultSummaryBar(result: result)
                    } else {
                        // Empty state
                        EmptyResultView()
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .frame(minWidth: 400)
            }

            Divider()

            // Status bar
            if viewModel.isProcessing {
                StatusBar(
                    isProcessing: viewModel.isProcessing,
                    progress: viewModel.progress,
                    statusMessage: viewModel.statusMessage
                )
            }

            // Error banner
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) {
                    viewModel.dismissError()
                }
                .padding(DesignSystem.Spacing.medium)
            }

            // Success banner
            if let success = viewModel.successMessage {
                SuccessBanner(message: success) {
                    viewModel.dismissSuccess()
                }
                .padding(DesignSystem.Spacing.medium)
            }
        }
        .background(DesignSystem.Colors.background)
    }
}

// MARK: - Header View

struct HeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ClinicalAnon")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Privacy-first clinical text anonymization")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Session info badge
            SessionInfoBadge()
        }
        .padding(DesignSystem.Spacing.medium)
        .background(DesignSystem.Colors.background)
    }
}

struct SessionInfoBadge: View {
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DesignSystem.Colors.success)
                .font(.system(size: 12))

            Text("Ready")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
    }
}

// MARK: - Empty Result View

struct EmptyResultView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Spacer()

            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 64))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))

            VStack(spacing: DesignSystem.Spacing.small) {
                Text("Ready to Anonymize")
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Enter clinical text on the left and click Analyze")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

@MainActor
class AnonymizationViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var inputText: String = ""
    @Published var result: AnonymizationResult?
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?

    // MARK: - Private Properties

    private let engine: AnonymizationEngine
    private let setupManager: SetupManager

    // MARK: - Initialization

    init(engine: AnonymizationEngine, setupManager: SetupManager) {
        self.engine = engine
        self.setupManager = setupManager

        // Subscribe to engine's published properties
        Task {
            for await _ in engine.$isProcessing.values {
                self.isProcessing = engine.isProcessing
                self.progress = engine.progress
                self.statusMessage = engine.statusMessage
            }
        }
    }

    // MARK: - Actions

    func analyze() async {
        guard !inputText.isEmpty else { return }

        // Dismiss previous messages
        errorMessage = nil
        successMessage = nil

        do {
            result = try await engine.anonymize(inputText)
            successMessage = "Anonymization complete! Found \(result?.entityCount ?? 0) entities."

            // Auto-dismiss success after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                successMessage = nil
            }
        } catch {
            if let appError = error as? AppError {
                errorMessage = appError.errorDescription ?? "An error occurred"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearAll() {
        inputText = ""
        result = nil
        engine.clearSession()
        errorMessage = nil
        successMessage = nil
    }

    func clearInputText() {
        inputText = ""
    }

    func copyInputText() {
        copyToClipboard(inputText)
        successMessage = "Original text copied to clipboard"
        autoHideSuccess()
    }

    func copyAnonymizedText() {
        guard let text = result?.anonymizedText else { return }
        copyToClipboard(text)
        successMessage = "Anonymized text copied to clipboard"
        autoHideSuccess()
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissSuccess() {
        successMessage = nil
    }

    // MARK: - Private Methods

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func autoHideSuccess() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AnonymizationView_Previews: PreviewProvider {
    static var previews: some View {
        AnonymizationView(
            ollamaService: OllamaService(mockMode: true),
            setupManager: SetupManager.preview
        )
        .frame(width: 1200, height: 700)
    }
}
#endif
