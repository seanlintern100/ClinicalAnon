//
//  AWSCredentialsManager.swift
//  Redactor
//
//  Purpose: Manages AWS credentials (built-in for internal use)
//  Organization: 3 Big Things
//

import Foundation

// MARK: - AWS Credentials

struct AWSCredentials: Codable, Equatable {
    var accessKeyId: String
    var secretAccessKey: String
    var region: String

    static let defaultRegion = "ap-southeast-2"

    var isValid: Bool {
        !accessKeyId.isEmpty && !secretAccessKey.isEmpty && !region.isEmpty
    }
}

// MARK: - AWS Credentials Manager

@MainActor
class AWSCredentialsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AWSCredentialsManager()

    // MARK: - Published Properties

    @Published var hasCredentials: Bool = false
    @Published var region: String = AWSCredentials.defaultRegion
    @Published var selectedModel: String = "apac.anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Built-in Credentials (internal use only)

    private let builtInAccessKey = "PLACEHOLDER_ACCESS_KEY"
    private let builtInSecretKey = "PLACEHOLDER_SECRET_KEY"
    private let builtInRegion = "ap-southeast-2"

    // MARK: - Defaults

    static let defaultModel = "apac.anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Available Models

    static let availableModels: [(id: String, name: String)] = [
        ("apac.anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4 (Default)"),
        ("apac.anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2"),
        ("apac.anthropic.claude-3-5-haiku-20241022-v1:0", "Claude 3.5 Haiku")
    ]

    // MARK: - Initialization

    init() {
        loadSettings()
        checkCredentials()
    }

    // MARK: - Credentials

    /// Load AWS credentials (built-in)
    func loadCredentials() -> AWSCredentials? {
        return AWSCredentials(
            accessKeyId: builtInAccessKey,
            secretAccessKey: builtInSecretKey,
            region: builtInRegion
        )
    }

    /// Check if credentials are available
    func checkCredentials() {
        hasCredentials = loadCredentials()?.isValid ?? false
        if let creds = loadCredentials() {
            region = creds.region
        }
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
