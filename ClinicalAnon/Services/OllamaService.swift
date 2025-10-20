//
//  OllamaService.swift
//  ClinicalAnon
//
//  Purpose: HTTP communication with Ollama for LLM processing
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Protocol Definition

protocol OllamaServiceProtocol {
    /// Send a request to Ollama with text and system prompt
    func sendRequest(text: String, systemPrompt: String) async throws -> String

    /// Check if Ollama is available and responding
    func checkConnection() async throws -> Bool
}

// MARK: - Ollama Service

class OllamaService: OllamaServiceProtocol {

    // MARK: - Properties

    private let baseURL = "http://localhost:11434"
    private let timeout: TimeInterval = 120.0  // 2 minutes for long prompts

    /// The model to use for requests (configurable)
    var modelName: String = "mistral:latest"

    /// Toggle mock mode for testing without Ollama
    var isMockMode: Bool = false

    // MARK: - Initialization

    init(mockMode: Bool = false) {
        self.isMockMode = mockMode
    }

    // MARK: - Public Methods

    func sendRequest(text: String, systemPrompt: String) async throws -> String {
        // Use mock response if in mock mode
        if isMockMode {
            return try await generateMockResponse(for: text)
        }

        // Build the request
        let request = try buildRequest(text: text, systemPrompt: systemPrompt)

        // Send with timeout
        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw AppError.ollamaNotRunning
            }
            throw AppError.networkError(NSError(
                domain: "OllamaService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
            ))
        }

        // Parse response
        let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)

        guard !ollamaResponse.response.isEmpty else {
            throw AppError.emptyResponse
        }

        return ollamaResponse.response
    }

    func checkConnection() async throws -> Bool {
        if isMockMode {
            return true
        }

        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0 // Quick check

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            throw AppError.connectionFailed
        }
    }

    // MARK: - Private Methods

    private func buildRequest(text: String, systemPrompt: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Construct the full prompt
        let fullPrompt = """
        \(systemPrompt)

        --- BEGIN TEXT ---
        \(text)
        --- END TEXT ---

        Return your response as valid JSON only.
        """

        // Build request body
        let requestBody = OllamaRequest(
            model: modelName,
            prompt: fullPrompt,
            stream: false,
            options: OllamaRequest.OllamaOptions(
                temperature: 0.1,  // Low temperature for consistent output
                num_predict: 2000   // Max tokens
            )
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        return request
    }

    // MARK: - Mock Mode

    private func generateMockResponse(for text: String) async throws -> String {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Generate a mock JSON response
        let mockJSON = """
        {
            "anonymized_text": "Mock anonymized version of the text. [CLIENT_A] attended session. [PROVIDER_A] conducted assessment on [DATE_A].",
            "entities": [
                {
                    "original": "Jane Smith",
                    "replacement": "CLIENT_A",
                    "type": "person_client",
                    "positions": [[0, 10]]
                },
                {
                    "original": "Dr. Wilson",
                    "replacement": "PROVIDER_A",
                    "type": "person_provider",
                    "positions": [[50, 60]]
                },
                {
                    "original": "March 15, 2024",
                    "replacement": "DATE_A",
                    "type": "date",
                    "positions": [[100, 114]]
                }
            ]
        }
        """

        return mockJSON
    }
}

// MARK: - Request/Response Models

/// Request structure for Ollama API
struct OllamaRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions?

    struct OllamaOptions: Codable {
        let temperature: Double?
        let num_predict: Int?
    }
}

/// Response structure from Ollama API
struct OllamaResponse: Codable {
    let model: String
    let created_at: String
    let response: String
    let done: Bool
}

/// Parsed LLM response for anonymization
struct LLMAnonymizationResponse: Codable {
    let anonymized_text: String
    let entities: [LLMEntity]

    struct LLMEntity: Codable {
        let original: String
        let replacement: String
        let type: String
        let positions: [[Int]]  // Array of [start, end] pairs
    }
}

// MARK: - Mock Service for Testing

class MockOllamaService: OllamaServiceProtocol {

    var shouldSucceed: Bool = true
    var delay: TimeInterval = 0.5

    func sendRequest(text: String, systemPrompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        if !shouldSucceed {
            throw AppError.networkError(NSError(domain: "Mock", code: -1))
        }

        return """
        {
            "anonymized_text": "Mock response for: \\(text.prefix(50))...",
            "entities": [
                {
                    "original": "Test Name",
                    "replacement": "CLIENT_A",
                    "type": "person_client",
                    "positions": [[0, 9]]
                }
            ]
        }
        """
    }

    func checkConnection() async throws -> Bool {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return shouldSucceed
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension OllamaService {
    /// Service in mock mode for previews
    static var preview: OllamaService {
        return OllamaService(mockMode: true)
    }

    /// Real service for testing
    static var real: OllamaService {
        return OllamaService(mockMode: false)
    }
}

extension MockOllamaService {
    /// Mock service that succeeds
    static var success: MockOllamaService {
        let service = MockOllamaService()
        service.shouldSucceed = true
        service.delay = 0.5
        return service
    }

    /// Mock service that fails
    static var failure: MockOllamaService {
        let service = MockOllamaService()
        service.shouldSucceed = false
        return service
    }
}
#endif
