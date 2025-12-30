//
//  LocalLLMService.swift
//  Redactor
//
//  Purpose: Local LLM integration via MLX Swift for PII review
//  Organization: 3 Big Things
//

import Foundation
import AppKit
import MLXLLM
import MLXLMCommon

// MARK: - PII Finding

struct PIIFinding {
    let text: String
    let suggestedType: EntityType
    let reason: String
    let confidence: Double
}

// MARK: - Model Info

struct LocalLLMModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let size: String
    let description: String
}

// MARK: - Local LLM Service

@MainActor
class LocalLLMService: ObservableObject {

    // MARK: - Singleton

    static let shared = LocalLLMService()

    // MARK: - Available Models

    static let availableModels: [LocalLLMModelInfo] = [
        LocalLLMModelInfo(
            id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            name: "Llama 3.1 8B (4-bit)",
            size: "~4.5 GB",
            description: "Best quality, recommended"
        ),
        LocalLLMModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama 3.2 3B (4-bit)",
            size: "~1.8 GB",
            description: "Faster, smaller"
        ),
        LocalLLMModelInfo(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen 2.5 7B (4-bit)",
            size: "~4 GB",
            description: "Good alternative"
        )
    ]

    // MARK: - Published Properties

    @Published var isAvailable: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    @Published var selectedModelId: String {
        didSet {
            UserDefaults.standard.set(selectedModelId, forKey: "localLLMModelId")
            // Unload current model when selection changes
            if isModelLoaded {
                unloadModel()
            }
        }
    }
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var chatSession: ChatSession?
    private let defaultModelId = "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"

    // MARK: - Prompt

    private let systemInstructions = """
        You find missed PII in redacted text. The text already has placeholders like [PERSON_A], [LOCATION_B], [NUM_A] - these are CORRECT, ignore them.

        Look ONLY for:
        - Raw names, emails, phone numbers that have NO placeholder
        - Partial leaks like "[PERSON_A]ohn" where "ohn" leaked after the placeholder

        Output format - one per line, nothing else:
        TYPE|exact_text|reason

        Types: NAME, EMAIL, PHONE, LOCATION, DATE, ID, OTHER

        Examples:
        NAME|John Smith|unredacted name
        EMAIL|test@email.com|unredacted email
        NAME|[PERSON_A]ohn|partial leak after placeholder

        If nothing missed, output only: NO_ISSUES_FOUND

        Do not explain. Do not list the existing placeholders. Only report NEW issues or output NO_ISSUES_FOUND.
        """

    // MARK: - Initialization

    private init() {
        selectedModelId = UserDefaults.standard.string(forKey: "localLLMModelId") ?? defaultModelId
        checkAvailability()
    }

    // MARK: - Public Methods

    /// Check if MLX is available (requires Apple Silicon)
    func checkAvailability() {
        // MLX requires Apple Silicon
        #if arch(arm64)
        isAvailable = true
        print("LocalLLMService: MLX available on Apple Silicon")
        #else
        isAvailable = false
        lastError = "MLX requires Apple Silicon (M1/M2/M3/M4)"
        print("LocalLLMService: MLX not available - Intel Mac detected")
        #endif
    }

    /// Get the selected model info
    var selectedModelInfo: LocalLLMModelInfo? {
        Self.availableModels.first { $0.id == selectedModelId }
    }

    /// Load the selected model (downloads if needed)
    func loadModel() async throws {
        guard isAvailable else {
            throw LocalLLMError.notAvailable
        }

        if isModelLoaded && modelContext != nil {
            print("LocalLLMService: Model already loaded")
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Preparing to download model..."
        lastError = nil

        print("LocalLLMService: Loading model: \(selectedModelId)")

        do {
            // Use the simple loadModel API from MLXLMCommon
            let context = try await MLXLMCommon.loadModel(
                id: selectedModelId
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                    if progress.fractionCompleted < 1.0 {
                        self?.downloadStatus = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                    } else {
                        self?.downloadStatus = "Loading model..."
                    }
                }
            }

            self.modelContext = context

            // Create chat session with the model
            let generateParams = GenerateParameters(
                maxTokens: 1000,
                temperature: 0.1,
                topP: 0.9
            )

            self.chatSession = ChatSession(
                context,
                instructions: systemInstructions,
                generateParameters: generateParams
            )

            self.isModelLoaded = true
            self.isDownloading = false
            self.downloadStatus = ""
            print("LocalLLMService: Model loaded successfully")

        } catch {
            isDownloading = false
            downloadStatus = ""
            print("LocalLLMService: Failed to load model: \(error)")
            lastError = "Failed to load model: \(error.localizedDescription)"
            throw LocalLLMError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Unload the current model to free memory
    func unloadModel() {
        modelContext = nil
        chatSession = nil
        isModelLoaded = false
        print("LocalLLMService: Model unloaded")
    }

    /// Review redacted text for missed PII
    func reviewForMissedPII(text: String) async throws -> [PIIFinding] {
        guard isAvailable else {
            throw LocalLLMError.notAvailable
        }

        // Load model if not already loaded
        if !isModelLoaded {
            try await loadModel()
        }

        guard let session = chatSession else {
            throw LocalLLMError.modelNotLoaded
        }

        isProcessing = true
        defer { isProcessing = false }

        let prompt = "Analyze this text for missed PII:\n\n\(text)"
        print("LocalLLMService: Starting PII review, prompt length: \(prompt.count) chars")
        print("LocalLLMService: Using model: \(selectedModelId)")

        let startTime = Date()

        do {
            // Use the simple ChatSession API
            let responseText = try await session.respond(to: prompt)

            let elapsed = Date().timeIntervalSince(startTime)
            print("LocalLLMService: Got response in \(String(format: "%.1f", elapsed))s, length: \(responseText.count) chars")
            print("LocalLLMService: Response: \(responseText)")

            let findings = parseFindings(response: responseText)
            print("LocalLLMService: Parsed \(findings.count) findings")
            return findings

        } catch {
            print("LocalLLMService: Generation failed: \(error)")
            throw LocalLLMError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// Parse LLM response into structured findings
    private func parseFindings(response: String) -> [PIIFinding] {
        var findings: [PIIFinding] = []

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines or "no issues" response
            if trimmed.isEmpty || trimmed.uppercased().contains("NO_ISSUES_FOUND") {
                continue
            }

            // Parse TYPE|text|reason format
            let parts = trimmed.components(separatedBy: "|")
            guard parts.count >= 2 else { continue }

            let typeStr = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            let reason = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : "Potential PII detected"

            // Skip if text is too short or looks like a placeholder itself
            guard text.count > 1 else { continue }

            let entityType = mapTypeToEntityType(typeStr)

            findings.append(PIIFinding(
                text: text,
                suggestedType: entityType,
                reason: reason,
                confidence: 0.8 // Default confidence for LLM findings
            ))
        }

        return findings
    }

    /// Map string type to EntityType
    private func mapTypeToEntityType(_ typeStr: String) -> EntityType {
        switch typeStr {
        case "NAME", "PERSON":
            return .personOther
        case "EMAIL", "PHONE", "CONTACT":
            return .contact
        case "LOCATION", "ADDRESS":
            return .location
        case "DATE":
            return .date
        case "ID", "IDENTIFIER":
            return .identifier
        default:
            return .personOther
        }
    }
}

// MARK: - Errors

enum LocalLLMError: LocalizedError {
    case notAvailable
    case modelNotLoaded
    case modelLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Local LLM requires Apple Silicon (M1/M2/M3/M4)."
        case .modelNotLoaded:
            return "Model is not loaded. Please load the model first."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Text generation failed: \(reason)"
        }
    }
}
