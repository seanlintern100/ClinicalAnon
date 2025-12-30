//
//  BedrockService.swift
//  Redactor
//
//  Purpose: Calls Bedrock via secure Lambda proxy (no AWS credentials on client)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Bedrock Service (Lambda Proxy)

@MainActor
class BedrockService: ObservableObject {

    // MARK: - Proxy Configuration

    /// Lambda proxy endpoint - API key provides authentication
    private let proxyEndpoint = "https://h9zrh24qaj.execute-api.ap-southeast-2.amazonaws.com/prod/invoke"
    private let apiKey = "hDHmW8hx8CGc7pibLcHkaOGBMzRRE6v2UAJnwfT7"

    // MARK: - Properties

    @Published var isConfigured: Bool = true  // Always configured with proxy
    @Published var lastError: BedrockError?

    // MARK: - Initialization

    init() {
        // No configuration needed - proxy handles AWS auth
    }

    // MARK: - Configuration (kept for API compatibility)

    /// Configure the service - no-op with proxy, kept for compatibility
    func configure(with credentials: AWSCredentials) async throws {
        // No configuration needed with proxy
        isConfigured = true
    }

    /// Test the connection with a simple request
    func testConnection() async throws -> Bool {
        let testMessages = [["role": "user", "content": "Say 'ok'"]]

        do {
            let _ = try await callProxy(
                model: "apac.anthropic.claude-3-5-haiku-20241022-v1:0",
                messages: testMessages,
                systemPrompt: nil,
                maxTokens: 10
            )
            return true
        } catch {
            throw BedrockError.connectionFailed(error.localizedDescription)
        }
    }

    // MARK: - Invoke Model

    /// Send a prompt to Claude and get a response (single message convenience)
    func invoke(
        systemPrompt: String?,
        userMessage: String,
        model: String,
        maxTokens: Int = 4096
    ) async throws -> String {
        let messages = [ChatMessage.user(userMessage)]
        return try await invoke(
            systemPrompt: systemPrompt,
            messages: messages,
            model: model,
            maxTokens: maxTokens
        )
    }

    /// Send a conversation to Claude and get a response (multi-message)
    func invoke(
        systemPrompt: String?,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int = 4096
    ) async throws -> String {

        // Convert ChatMessage array to dictionary array for JSON
        let messageArray = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        do {
            let response = try await callProxy(
                model: model,
                messages: messageArray,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens
            )
            return response
        } catch let error as BedrockError {
            lastError = error
            throw error
        } catch {
            let bedrockError = BedrockError.invocationFailed(error.localizedDescription)
            lastError = bedrockError
            throw bedrockError
        }
    }

    /// Send a prompt and stream the response (single message convenience)
    /// Note: Lambda proxy doesn't support true streaming, returns complete response
    func invokeStreaming(
        systemPrompt: String?,
        userMessage: String,
        model: String,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        let messages = [ChatMessage.user(userMessage)]
        return invokeStreaming(
            systemPrompt: systemPrompt,
            messages: messages,
            model: model,
            maxTokens: maxTokens
        )
    }

    /// Send a conversation and stream the response (multi-message)
    /// Note: Lambda proxy collects stream and returns complete response
    func invokeStreaming(
        systemPrompt: String?,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Convert ChatMessage array to dictionary array
                    let messageArray = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

                    // Call proxy (streaming mode collects all chunks server-side)
                    let response = try await self.callProxy(
                        model: model,
                        messages: messageArray,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        stream: true
                    )

                    // Yield the complete response
                    continuation.yield(response)
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: BedrockError.streamingFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Private Proxy Call

    private func callProxy(
        model: String,
        messages: [[String: String]],
        systemPrompt: String?,
        maxTokens: Int,
        stream: Bool = false
    ) async throws -> String {

        guard let url = URL(string: proxyEndpoint) else {
            throw BedrockError.configurationFailed("Invalid proxy URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 120  // 2 minute timeout for long responses

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": stream
        ]

        if let system = systemPrompt, !system.isEmpty {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BedrockError.invocationFailed("Invalid response")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BedrockError.emptyResponse
        }

        // Check for error response
        if let error = json["error"] as? String {
            switch httpResponse.statusCode {
            case 429:
                throw BedrockError.throttled
            case 403:
                throw BedrockError.accessDenied
            default:
                throw BedrockError.invocationFailed(error)
            }
        }

        // Extract text from response
        if let content = json["content"] as? [[String: Any]],
           let firstBlock = content.first,
           let text = firstBlock["text"] as? String {
            return text
        }

        throw BedrockError.emptyResponse
    }
}

// MARK: - Bedrock Errors

enum BedrockError: LocalizedError {
    case notConfigured
    case configurationFailed(String)
    case connectionFailed(String)
    case invocationFailed(String)
    case streamingFailed(String)
    case emptyResponse
    case throttled
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Bedrock service is not configured."
        case .configurationFailed(let message):
            return "Failed to configure: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .invocationFailed(let message):
            return "AI request failed: \(message)"
        case .streamingFailed(let message):
            return "Streaming failed: \(message)"
        case .emptyResponse:
            return "Received empty response from AI"
        case .throttled:
            return "Request was throttled. Please try again in a moment."
        case .accessDenied:
            return "Access denied to AI service."
        }
    }
}
