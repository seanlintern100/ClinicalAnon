//
//  LocalLLMService.swift
//  Redactor
//
//  Purpose: Local LLM integration via Ollama for PII review
//  Organization: 3 Big Things
//

import Foundation

// MARK: - PII Finding

struct PIIFinding {
    let text: String
    let suggestedType: EntityType
    let reason: String
    let confidence: Double
}

// MARK: - Local LLM Service

@MainActor
class LocalLLMService: ObservableObject {

    // MARK: - Singleton

    static let shared = LocalLLMService()

    // MARK: - Published Properties

    @Published var isAvailable: Bool = false
    @Published var availableModels: [String] = []
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "localLLMModel")
        }
    }
    @Published var isProcessing: Bool = false
    @Published var lastError: String?

    // MARK: - Private Properties

    private let ollamaEndpoint = "http://localhost:11434"
    private let defaultModel = "llama3.1:8b"
    private let requestTimeout: TimeInterval = 180 // 3 minutes

    // MARK: - Prompt

    private let piiReviewPrompt = """
        This text has been redacted with placeholders like [PERSON_A], [LOCATION_B], etc. Find any PII that was missed or partially redacted:
        - Unredacted names, emails, phone numbers, addresses
        - Malformed placeholders (e.g., [PERSON_X]ohn where part of the name leaked)
        - Any identifiable information

        Return each issue on its own line in this exact format:
        TYPE|exact text found|reason

        Valid TYPEs: NAME, EMAIL, PHONE, LOCATION, DATE, ID, OTHER

        Example output:
        EMAIL|john@example.com|unredacted email address
        NAME|[PERSON_V]eaver|partial name leak - 'eaver' visible after placeholder

        If no issues found, respond with: NO_ISSUES_FOUND

        Text to analyze:
        """

    // MARK: - Initialization

    private init() {
        selectedModel = UserDefaults.standard.string(forKey: "localLLMModel") ?? defaultModel
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Public Methods

    /// Check if Ollama is running and has models available
    func checkAvailability() async {
        do {
            let models = try await fetchAvailableModels()
            availableModels = models
            isAvailable = !models.isEmpty

            // If selected model not in list, default to first available or default
            if !models.contains(selectedModel) {
                if models.contains(defaultModel) {
                    selectedModel = defaultModel
                } else if let first = models.first {
                    selectedModel = first
                }
            }

            lastError = nil
        } catch {
            isAvailable = false
            availableModels = []
            lastError = "Ollama not running"
        }
    }

    /// Review redacted text for missed PII
    func reviewForMissedPII(text: String) async throws -> [PIIFinding] {
        guard isAvailable else {
            throw LocalLLMError.notAvailable
        }

        isProcessing = true
        defer { isProcessing = false }

        let fullPrompt = piiReviewPrompt + "\n\n" + text

        let response = try await sendPrompt(fullPrompt)

        return parseFindings(response: response)
    }

    // MARK: - Private Methods

    /// Fetch list of available models from Ollama
    private func fetchAvailableModels() async throws -> [String] {
        guard let url = URL(string: "\(ollamaEndpoint)/api/tags") else {
            throw LocalLLMError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LocalLLMError.connectionFailed
        }

        struct ModelsResponse: Codable {
            struct Model: Codable {
                let name: String
            }
            let models: [Model]
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.models.map { $0.name }
    }

    /// Send prompt to Ollama and get response
    private func sendPrompt(_ prompt: String) async throws -> String {
        guard let url = URL(string: "\(ollamaEndpoint)/api/generate") else {
            throw LocalLLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout

        struct GenerateRequest: Codable {
            let model: String
            let prompt: String
            let stream: Bool
        }

        let requestBody = GenerateRequest(
            model: selectedModel,
            prompt: prompt,
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalLLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw LocalLLMError.requestFailed(statusCode: httpResponse.statusCode)
        }

        struct GenerateResponse: Codable {
            let response: String
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response
    }

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
    case invalidURL
    case connectionFailed
    case invalidResponse
    case requestFailed(statusCode: Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Local LLM is not available. Please start Ollama."
        case .invalidURL:
            return "Invalid Ollama endpoint URL."
        case .connectionFailed:
            return "Could not connect to Ollama. Is it running?"
        case .invalidResponse:
            return "Invalid response from Ollama."
        case .requestFailed(let statusCode):
            return "Request failed with status code: \(statusCode)"
        case .timeout:
            return "Request timed out. The model may be loading."
        }
    }
}
