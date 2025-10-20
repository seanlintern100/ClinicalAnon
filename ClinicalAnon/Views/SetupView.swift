//
//  SetupView.swift
//  ClinicalAnon
//
//  Purpose: Setup wizard UI for Ollama installation and configuration
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Setup View

struct SetupView: View {

    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        ZStack {
            // Background
            DesignSystem.Colors.background
                .ignoresSafeArea()

            VStack(spacing: DesignSystem.Spacing.large) {
                // Content based on state
                switch setupManager.state {
                case .checking:
                    CheckingView()

                case .ready:
                    ReadyView()

                case .needsHomebrew:
                    NeedsHomebrewView(setupManager: setupManager)

                case .needsOllama:
                    NeedsOllamaView(setupManager: setupManager)

                case .needsModel:
                    NeedsModelView(setupManager: setupManager)

                case .selectingModel:
                    ModelSelectionView(setupManager: setupManager)

                case .downloadingModel(let progress):
                    DownloadingModelView(
                        progress: progress,
                        status: setupManager.downloadStatus
                    )

                case .startingOllama:
                    StartingOllamaView()

                case .error(let message):
                    ErrorView(message: message, setupManager: setupManager)
                }
            }
            .frame(maxWidth: 600)
            .padding(DesignSystem.Spacing.xxlarge)
        }
    }
}

// MARK: - Checking View

struct CheckingView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(DesignSystem.Colors.primaryTeal)

            Text("Checking setup...")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

// MARK: - Ready View

struct ReadyView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("✅")
                .font(.system(size: 64))

            Text("Ready to Go!")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            Text("All components are installed and ready.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Needs Homebrew View

struct NeedsHomebrewView: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("🍺")
                    .font(.system(size: 48))

                Text("Homebrew Required")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Homebrew is needed to install Ollama. It's a package manager for macOS.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(height: DesignSystem.Spacing.medium)

            // Instructions
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                Text("Installation Steps:")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                InstructionStep(
                    number: 1,
                    text: "Open Terminal (found in Applications > Utilities)"
                )

                InstructionStep(
                    number: 2,
                    text: "Copy the command below"
                )

                InstructionStep(
                    number: 3,
                    text: "Paste into Terminal and press Enter"
                )

                InstructionStep(
                    number: 4,
                    text: "Follow the prompts to install"
                )

                InstructionStep(
                    number: 5,
                    text: "Come back here when done"
                )
            }
            .padding(DesignSystem.Spacing.medium)
            .cardStyle()

            // Command to copy
            CommandBox(
                command: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                onCopy: { setupManager.copyHomebrewInstallCommand() }
            )

            Spacer()

            // Action buttons
            HStack(spacing: DesignSystem.Spacing.medium) {
                Button("Check Again") {
                    Task { await setupManager.checkSetup() }
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Link("Learn More", destination: URL(string: "https://brew.sh")!)
                    .font(DesignSystem.Typography.button)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)
            }
        }
    }
}

// MARK: - Needs Ollama View

struct NeedsOllamaView: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("🚀")
                    .font(.system(size: 48))

                Text("Ollama Required")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Ollama runs the AI model locally on your Mac for complete privacy.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(height: DesignSystem.Spacing.medium)

            // Option 1: Automatic
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("✅ OPTION 1: Automatic Install")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("We'll open Terminal with the install command ready.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Button("Install Ollama Automatically") {
                    Task {
                        try? await setupManager.installOllama()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(DesignSystem.Spacing.medium)
            .cardStyle()

            // Option 2: Manual
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                Text("📖 OPTION 2: Manual Install")
                    .font(DesignSystem.Typography.subheading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text("Run this command in Terminal:")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                CommandBox(
                    command: "brew install ollama",
                    onCopy: { setupManager.copyOllamaInstallCommand() }
                )
            }
            .padding(DesignSystem.Spacing.medium)
            .cardStyle()

            Spacer()

            // Action button
            Button("Check Again") {
                Task { await setupManager.checkSetup() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - Model Selection View

struct ModelSelectionView: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("🤖")
                    .font(.system(size: 48))

                Text("Select AI Model")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("Choose which model to use for anonymization. You can download additional models or use one you already have.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(height: DesignSystem.Spacing.medium)

            // Model list
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.small) {
                    let installedModels = setupManager.getInstalledModels()

                    ForEach(setupManager.availableModels) { model in
                        ModelRow(
                            model: model,
                            isInstalled: installedModels.contains(model.name),
                            isSelected: setupManager.selectedModel == model.name,
                            onSelect: {
                                setupManager.selectedModel = model.name
                            },
                            onDownload: {
                                Task {
                                    try? await setupManager.downloadModel(modelName: model.name)
                                }
                            }
                        )
                    }
                }
            }

            Spacer()

            // Continue button
            Button("Continue with \(setupManager.availableModels.first(where: { $0.name == setupManager.selectedModel })?.displayName ?? "Selected Model")") {
                Task { await setupManager.checkSetup() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!setupManager.getInstalledModels().contains(setupManager.selectedModel))
        }
    }
}

struct ModelRow: View {
    let model: ModelInfo
    let isInstalled: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            // Selection radio
            Button(action: isInstalled ? onSelect : {}) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? DesignSystem.Colors.primaryTeal : DesignSystem.Colors.textSecondary)
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(!isInstalled)

            // Model info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack {
                    Text(model.displayName)
                        .font(DesignSystem.Typography.subheading)
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    if isInstalled {
                        Text("INSTALLED")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.success)
                            .padding(.horizontal, DesignSystem.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.success.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Text(model.description)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text("Size: \(model.size)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            Spacer()

            // Download button
            if !isInstalled {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .cardStyle()
    }
}

// MARK: - Needs Model View

struct NeedsModelView: View {
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
            // Header
            VStack(spacing: DesignSystem.Spacing.small) {
                Text("📦")
                    .font(.system(size: 48))

                Text("Download AI Model")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.primaryTeal)

                Text("One-time download of the selected model. This works completely offline afterwards.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(height: DesignSystem.Spacing.xlarge)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.success)
                    Text("Ollama is installed")
                        .font(DesignSystem.Typography.body)
                }

                HStack {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(DesignSystem.Colors.orange)
                    Text("Model needs to be downloaded")
                        .font(DesignSystem.Typography.body)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .cardStyle()

            Spacer()

            VStack(spacing: DesignSystem.Spacing.small) {
                Text("💡 Current model: \(setupManager.availableModels.first(where: { $0.name == setupManager.selectedModel })?.displayName ?? setupManager.selectedModel)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: DesignSystem.Spacing.medium) {
                    Button("Choose Different Model") {
                        setupManager.state = .selectingModel
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button("Download \(setupManager.availableModels.first(where: { $0.name == setupManager.selectedModel })?.displayName ?? "Model")") {
                        Task {
                            try? await setupManager.downloadModel()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }
}

// MARK: - Downloading Model View

struct DownloadingModelView: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            // Header
            Text("📦")
                .font(.system(size: 48))

            Text("Downloading Model")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.primaryTeal)

            Spacer()
                .frame(height: DesignSystem.Spacing.xlarge)

            // Progress bar
            VStack(spacing: DesignSystem.Spacing.medium) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(DesignSystem.Colors.primaryTeal)
                    .frame(height: 8)

                Text("\(Int(progress * 100))%")
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if !status.isEmpty {
                    Text(status)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(DesignSystem.Spacing.large)
            .cardStyle()

            Spacer()

            Text("This may take several minutes depending on your internet speed...")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Starting Ollama View

struct StartingOllamaView: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(DesignSystem.Colors.primaryTeal)

            Text("Starting Ollama...")
                .font(DesignSystem.Typography.heading)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Text("The AI service is launching")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Text("⚠️")
                .font(.system(size: 48))

            Text("Setup Error")
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.error)

            Text(message)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(DesignSystem.Spacing.medium)
                .cardStyle()

            Spacer()

            Button("Try Again") {
                Task { await setupManager.checkSetup() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Helper Components

struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Text("\(number).")
                .font(DesignSystem.Typography.bodyBold)
                .foregroundColor(DesignSystem.Colors.primaryTeal)
                .frame(width: 24, alignment: .leading)

            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

struct CommandBox: View {
    let command: String
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text(command)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Spacer()

                Button(action: {
                    onCopy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy")
                    }
                    .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(DesignSystem.Spacing.small)
        .background(DesignSystem.Colors.surface)
        .cornerRadius(DesignSystem.CornerRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(
                configuration.isPressed
                    ? DesignSystem.Colors.primaryTeal.opacity(0.8)
                    : DesignSystem.Colors.primaryTeal
            )
            .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.button)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(
                configuration.isPressed
                    ? DesignSystem.Colors.surface.opacity(0.8)
                    : DesignSystem.Colors.surface
            )
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
}

// MARK: - Preview

#if DEBUG
struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SetupView()
                .frame(width: 800, height: 600)
                .previewDisplayName("Default")
        }
    }
}
#endif
