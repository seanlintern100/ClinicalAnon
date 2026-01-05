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

    /// Lambda Function URL for Bedrock calls (bypasses API Gateway 29s timeout limit)
    private let proxyEndpoint = "https://h7qgngqj752gsfujntpvqj22ky0urohg.lambda-url.ap-southeast-2.on.aws/"

    /// Endpoint to fetch current API key (rotates weekly)
    private let getKeyEndpoint = "https://h9zrh24qaj.execute-api.ap-southeast-2.amazonaws.com/prod/get-api-key"

    /// Bundle ID sent to validate app identity
    private let bundleId = Bundle.main.bundleIdentifier ?? "com.3bigthings.Redactor"

    // MARK: - Properties

    @Published var isConfigured: Bool = false
    @Published var lastError: AppError?

    /// Cached API key (fetched on init)
    private var apiKey: String?

    // MARK: - Initialization

    init() {
        // Fetch API key on initialization
        Task {
            await fetchApiKey()
        }
    }

    // MARK: - API Key Fetching

    /// Fetch the current API key from the secure endpoint
    private func fetchApiKey() async {
        guard let url = URL(string: getKeyEndpoint) else {
            lastError = .awsConfigurationFailed("Invalid get-key URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(bundleId, forHTTPHeaderField: "X-Bundle-Id")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = .awsConfigurationFailed("Invalid response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                lastError = .awsConfigurationFailed("Failed to fetch API key: \(httpResponse.statusCode)")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = json["apiKey"] as? String else {
                lastError = .awsConfigurationFailed("Invalid API key response")
                return
            }

            apiKey = key
            isConfigured = true
            lastError = nil

        } catch {
            lastError = .awsConfigurationFailed("Network error: \(error.localizedDescription)")
        }
    }

    /// Manually refresh the API key (if needed)
    func refreshApiKey() async {
        await fetchApiKey()
    }

    // MARK: - Configuration (kept for API compatibility)

    /// Configure the service - no-op with proxy, kept for compatibility
    func configure(with credentials: AWSCredentials) async throws {
        // Ensure we have an API key
        if apiKey == nil {
            await fetchApiKey()
        }

        if apiKey == nil {
            throw AppError.aiNotConfigured
        }
    }

    /// Test the connection with a simple request
    func testConnection() async throws -> Bool {
        // Ensure we have an API key first
        if apiKey == nil {
            await fetchApiKey()
        }

        guard apiKey != nil else {
            throw AppError.aiNotConfigured
        }

        let testMessages = [["role": "user", "content": "Say 'ok'"]]

        do {
            // Use Sonnet 4 for connection test (Haiku may have access restrictions)
            let _ = try await callProxy(
                model: "apac.anthropic.claude-sonnet-4-20250514-v1:0",
                messages: testMessages,
                systemPrompt: nil,
                maxTokens: 10
            )
            return true
        } catch {
            throw AppError.awsConnectionFailed(error.localizedDescription)
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

        // Ensure we have an API key
        if apiKey == nil {
            await fetchApiKey()
        }

        guard apiKey != nil else {
            throw AppError.aiNotConfigured
        }

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
        } catch let error as AppError {
            lastError = error
            throw error
        } catch {
            let appError = AppError.awsInvocationFailed(error.localizedDescription)
            lastError = appError
            throw appError
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
                    // Ensure we have an API key
                    if self.apiKey == nil {
                        await self.fetchApiKey()
                    }

                    guard self.apiKey != nil else {
                        continuation.finish(throwing: AppError.aiNotConfigured)
                        return
                    }

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
                    continuation.finish(throwing: AppError.awsStreamingFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Invoke with Tools

    /// Send a conversation with tools enabled and get a response that may contain tool use
    func invokeWithTools(
        systemPrompt: String?,
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = 4096,
        betas: [String] = ["context-management-2025-06-27"]
    ) async throws -> AIResponse {

        // Ensure we have an API key
        if apiKey == nil {
            await fetchApiKey()
        }

        guard apiKey != nil else {
            throw AppError.aiNotConfigured
        }

        do {
            let response = try await callProxyWithTools(
                model: model,
                messages: messages,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                tools: tools,
                betas: betas
            )
            return response
        } catch let error as AppError {
            lastError = error
            throw error
        } catch {
            let appError = AppError.awsInvocationFailed(error.localizedDescription)
            lastError = appError
            throw appError
        }
    }

    // MARK: - Private Proxy Calls

    private func callProxyWithTools(
        model: String,
        messages: [[String: Any]],
        systemPrompt: String?,
        maxTokens: Int,
        tools: [[String: Any]],
        betas: [String]
    ) async throws -> AIResponse {

        guard let currentApiKey = apiKey else {
            throw AppError.aiNotConfigured
        }

        guard let url = URL(string: proxyEndpoint) else {
            throw AppError.awsConfigurationFailed("Invalid proxy URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentApiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 300  // 5 min to match Lambda timeout

        // Build request body with tools
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "tools": tools
        ]

        if !betas.isEmpty {
            body["betas"] = betas
        }

        if let system = systemPrompt, !system.isEmpty {
            body["system"] = system
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("🔵 Bedrock invokeWithTools: Sending request")
        print("   Model: \(model)")
        print("   Tools: \(tools.count)")
        print("   Messages: \(messages.count)")
        #endif

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.awsInvocationFailed("Invalid response")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("🔴 Bedrock: Failed to parse JSON response")
            print("   Raw data: \(String(data: data, encoding: .utf8) ?? "nil")")
            #endif
            throw AppError.emptyResponse
        }

        #if DEBUG
        print("🔵 Bedrock response status: \(httpResponse.statusCode)")
        print("   Response keys: \(json.keys)")
        print("   Stop reason: \(json["stop_reason"] ?? "nil")")
        #endif

        // Check for error response
        if let error = json["error"] as? String {
            switch httpResponse.statusCode {
            case 429:
                throw AppError.aiThrottled
            case 403:
                await fetchApiKey()
                throw AppError.aiAccessDenied
            default:
                throw AppError.awsInvocationFailed(error)
            }
        }

        // Parse content blocks
        guard let content = json["content"] as? [[String: Any]] else {
            #if DEBUG
            print("🔴 Bedrock: No content array in response")
            print("   Full response: \(json)")
            #endif
            throw AppError.emptyResponse
        }

        var textContent: String?
        var toolUse: ToolUse?
        let stopReason = json["stop_reason"] as? String

        for block in content {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String {
                    textContent = text
                }
            case "tool_use":
                if let toolId = block["id"] as? String,
                   let toolName = block["name"] as? String,
                   let toolInput = block["input"] as? [String: Any] {
                    // Convert input to AnyCodable
                    var codableInput: [String: AnyCodable] = [:]
                    for (key, value) in toolInput {
                        codableInput[key] = AnyCodable(value)
                    }
                    toolUse = ToolUse(id: toolId, name: toolName, input: codableInput)

                    #if DEBUG
                    print("🔵 Tool use detected: \(toolName)")
                    print("   Tool ID: \(toolId)")
                    print("   Input: \(toolInput)")
                    #endif
                }
            default:
                break
            }
        }

        return AIResponse(text: textContent, toolUse: toolUse, stopReason: stopReason)
    }

    private func callProxy(
        model: String,
        messages: [[String: String]],
        systemPrompt: String?,
        maxTokens: Int,
        stream: Bool = false
    ) async throws -> String {

        guard let currentApiKey = apiKey else {
            throw AppError.aiNotConfigured
        }

        guard let url = URL(string: proxyEndpoint) else {
            throw AppError.awsConfigurationFailed("Invalid proxy URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentApiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 300  // 5 min to match Lambda timeout

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
            throw AppError.awsInvocationFailed("Invalid response")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            #if DEBUG
            print("🔴 Bedrock: Failed to parse JSON response")
            print("   Raw data: \(String(data: data, encoding: .utf8) ?? "nil")")
            #endif
            throw AppError.emptyResponse
        }

        #if DEBUG
        print("🔵 Bedrock response status: \(httpResponse.statusCode)")
        print("   Response keys: \(json.keys)")
        if json["error"] != nil {
            print("   Error: \(json["error"] ?? "nil")")
        }
        #endif

        // Check for error response
        if let error = json["error"] as? String {
            switch httpResponse.statusCode {
            case 429:
                throw AppError.aiThrottled
            case 403:
                // API key might have rotated - try refreshing
                await fetchApiKey()
                throw AppError.aiAccessDenied
            default:
                throw AppError.awsInvocationFailed(error)
            }
        }

        // Extract text from response
        if let content = json["content"] as? [[String: Any]],
           let firstBlock = content.first,
           let text = firstBlock["text"] as? String {
            return text
        }

        #if DEBUG
        print("🔴 Bedrock: No content.text in response")
        print("   Full response: \(json)")
        #endif
        throw AppError.emptyResponse
    }
}

