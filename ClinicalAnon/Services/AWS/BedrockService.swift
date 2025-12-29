//
//  BedrockService.swift
//  Redactor
//
//  Purpose: Wraps AWS Bedrock Runtime for Claude API calls
//  Organization: 3 Big Things
//

import Foundation
import AWSBedrockRuntime
import AWSSDKIdentity
import Smithy

// MARK: - Bedrock Service

@MainActor
class BedrockService: ObservableObject {

    // MARK: - Properties

    @Published var isConfigured: Bool = false
    @Published var lastError: BedrockError?

    private var client: BedrockRuntimeClient?
    private var credentials: AWSCredentials?

    // MARK: - Configuration

    /// Configure the service with AWS credentials
    func configure(with credentials: AWSCredentials) async throws {
        self.credentials = credentials

        do {
            // Create static credentials provider
            let staticCredentials = AWSCredentialIdentity(
                accessKey: credentials.accessKeyId,
                secret: credentials.secretAccessKey
            )

            let credentialsProvider = try StaticAWSCredentialIdentityResolver(staticCredentials)

            // Create Bedrock Runtime client configuration
            let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(
                awsCredentialIdentityResolver: credentialsProvider,
                region: credentials.region
            )

            client = BedrockRuntimeClient(config: config)
            isConfigured = true
            lastError = nil

        } catch {
            isConfigured = false
            lastError = .configurationFailed(error.localizedDescription)
            throw lastError!
        }
    }

    /// Test the connection with a simple request
    func testConnection() async throws -> Bool {
        guard let client = client, let credentials = credentials else {
            throw BedrockError.notConfigured
        }

        // Try a minimal invoke to test credentials
        let testPrompt = "Say 'ok'"

        let requestBody = ClaudeRequestBody(
            anthropic_version: "bedrock-2023-05-31",
            max_tokens: 10,
            messages: [
                ClaudeMessage(role: "user", content: testPrompt)
            ]
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        let input = InvokeModelInput(
            body: bodyData,
            contentType: "application/json",
            modelId: credentials.region.contains("apac") ?
                "apac.anthropic.claude-3-5-haiku-20241022-v1:0" :
                "anthropic.claude-3-5-haiku-20241022-v1:0"
        )

        do {
            let _ = try await client.invokeModel(input: input)
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
        // Convert single message to array and call the array version
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

        guard let client = client else {
            throw BedrockError.notConfigured
        }

        // Convert ChatMessage array to ClaudeMessage array
        let claudeMessages = messages.map { ClaudeMessage(role: $0.role.rawValue, content: $0.content) }

        let requestBody = ClaudeRequestBody(
            anthropic_version: "bedrock-2023-05-31",
            max_tokens: maxTokens,
            system: systemPrompt,
            messages: claudeMessages
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        let input = InvokeModelInput(
            body: bodyData,
            contentType: "application/json",
            modelId: model
        )

        do {
            let output = try await client.invokeModel(input: input)

            guard let responseData = output.body else {
                throw BedrockError.emptyResponse
            }

            let decoder = JSONDecoder()
            let response = try decoder.decode(ClaudeResponse.self, from: responseData)

            // Extract text from content blocks
            let text = response.content
                .compactMap { block -> String? in
                    if case .text(let text) = block {
                        return text
                    }
                    return nil
                }
                .joined()

            return text

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
    func invokeStreaming(
        systemPrompt: String?,
        userMessage: String,
        model: String,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {
        // Convert single message to array and call the array version
        let messages = [ChatMessage.user(userMessage)]
        return invokeStreaming(
            systemPrompt: systemPrompt,
            messages: messages,
            model: model,
            maxTokens: maxTokens
        )
    }

    /// Send a conversation and stream the response (multi-message)
    func invokeStreaming(
        systemPrompt: String?,
        messages: [ChatMessage],
        model: String,
        maxTokens: Int = 4096
    ) -> AsyncThrowingStream<String, Error> {

        AsyncThrowingStream { continuation in
            Task {
                guard let client = self.client else {
                    continuation.finish(throwing: BedrockError.notConfigured)
                    return
                }

                // Convert ChatMessage array to ClaudeMessage array
                let claudeMessages = messages.map { ClaudeMessage(role: $0.role.rawValue, content: $0.content) }

                let requestBody = ClaudeRequestBody(
                    anthropic_version: "bedrock-2023-05-31",
                    max_tokens: maxTokens,
                    system: systemPrompt,
                    messages: claudeMessages
                )

                do {
                    let encoder = JSONEncoder()
                    let bodyData = try encoder.encode(requestBody)

                    let input = InvokeModelWithResponseStreamInput(
                        body: bodyData,
                        contentType: "application/json",
                        modelId: model
                    )

                    let output = try await client.invokeModelWithResponseStream(input: input)

                    guard let stream = output.body else {
                        continuation.finish(throwing: BedrockError.emptyResponse)
                        return
                    }

                    for try await event in stream {
                        if case .chunk(let payload) = event {
                            if let bytes = payload.bytes {
                                // Parse the streaming event
                                if let text = self.parseStreamingChunk(bytes) {
                                    continuation.yield(text)
                                }
                            }
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: BedrockError.streamingFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func parseStreamingChunk(_ data: Data) -> String? {
        do {
            let decoder = JSONDecoder()
            let event = try decoder.decode(StreamingEvent.self, from: data)

            switch event.type {
            case "content_block_delta":
                return event.delta?.text
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Request/Response Models

private struct ClaudeRequestBody: Encodable {
    let anthropic_version: String
    let max_tokens: Int
    var system: String?
    let messages: [ClaudeMessage]
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let stop_reason: String?
}

private enum ContentBlock: Decodable {
    case text(String)
    case other

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other
        }
    }
}

private struct StreamingEvent: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
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
            return "AWS Bedrock is not configured. Please add your credentials in Settings."
        case .configurationFailed(let message):
            return "Failed to configure AWS: \(message)"
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
            return "Access denied. Check your AWS credentials and permissions."
        }
    }
}
