//
//  AWSCredentialsManager.swift
//  Redactor
//
//  Purpose: Manages AWS credentials from environment variables
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

    // MARK: - Environment Variable Names

    private let envAccessKey = "AWS_ACCESS_KEY_ID"
    private let envSecretKey = "AWS_SECRET_ACCESS_KEY"
    private let envRegion = "AWS_REGION"

    // MARK: - Computed Properties (for easy access)

    var accessKeyId: String? {
        ProcessInfo.processInfo.environment[envAccessKey]
    }

    var secretAccessKey: String? {
        ProcessInfo.processInfo.environment[envSecretKey]
    }

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

    // MARK: - Credentials from Environment

    /// Load AWS credentials from environment variables
    func loadCredentials() -> AWSCredentials? {
        guard let accessKeyId = ProcessInfo.processInfo.environment[envAccessKey],
              let secretAccessKey = ProcessInfo.processInfo.environment[envSecretKey] else {
            return nil
        }

        let region = ProcessInfo.processInfo.environment[envRegion] ?? AWSCredentials.defaultRegion

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region
        )
    }

    /// Check if credentials exist in environment
    func checkCredentials() {
        hasCredentials = loadCredentials()?.isValid ?? false
        if let creds = loadCredentials() {
            region = creds.region
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        // Model selection can still be saved in UserDefaults
        if let savedModel = UserDefaults.standard.string(forKey: "aws_model") {
            selectedModel = savedModel
        }
    }

    func saveModel(_ modelId: String) {
        UserDefaults.standard.set(modelId, forKey: "aws_model")
        selectedModel = modelId
    }
}
