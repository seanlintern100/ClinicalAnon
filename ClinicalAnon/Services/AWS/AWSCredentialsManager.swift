//
//  AWSCredentialsManager.swift
//  Redactor
//
//  Purpose: Manages model selection (credentials handled by Lambda proxy)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - AWS Credentials (kept for API compatibility)

struct AWSCredentials: Codable, Equatable {
    var accessKeyId: String
    var secretAccessKey: String
    var region: String

    static let defaultRegion = "ap-southeast-2"

    var isValid: Bool {
        // Always valid with proxy - credentials not needed on client
        true
    }
}

// MARK: - AWS Credentials Manager

@MainActor
class AWSCredentialsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AWSCredentialsManager()

    // MARK: - Published Properties

    @Published var hasCredentials: Bool = true  // Always true with proxy
    @Published var region: String = AWSCredentials.defaultRegion
    @Published var selectedModel: String = "apac.anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Defaults

    static let defaultModel = "apac.anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Available Models

    static let availableModels: [(id: String, name: String)] = [
        ("apac.anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4 (Recommended)"),
        ("apac.anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2")
    ]

    // MARK: - Initialization

    init() {
        loadSettings()
    }

    // MARK: - Credentials (no-op with proxy, kept for compatibility)

    func loadCredentials() -> AWSCredentials? {
        // Return dummy credentials - proxy handles real auth
        return AWSCredentials(
            accessKeyId: "proxy",
            secretAccessKey: "proxy",
            region: region
        )
    }

    func checkCredentials() {
        // Always has credentials with proxy
        hasCredentials = true
    }

    // MARK: - Settings

    private func loadSettings() {
        if let savedModel = UserDefaults.standard.string(forKey: "aws_model") {
            selectedModel = savedModel
        }
    }

    func saveModel(_ modelId: String) {
        UserDefaults.standard.set(modelId, forKey: "aws_model")
        selectedModel = modelId
    }
}
