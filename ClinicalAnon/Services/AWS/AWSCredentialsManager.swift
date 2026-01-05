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
    @Published var selectedModel: String = "au.anthropic.claude-sonnet-4-5-20250929-v1:0"

    // MARK: - Defaults

    static let defaultModel = "au.anthropic.claude-sonnet-4-5-20250929-v1:0"

    // MARK: - Available Models
    // Note: Only au. prefix models keep data within Australia (data sovereignty)
    // Enable in AWS Console → Bedrock → Model access

    static let availableModels: [(id: String, name: String)] = [
        ("au.anthropic.claude-sonnet-4-5-20250929-v1:0", "Claude Sonnet 4.5 (Recommended)"),
        ("au.anthropic.claude-haiku-4-5-20251001-v1:0", "Claude Haiku 4.5 (Faster, Lower Cost)")
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
        if let savedModel = UserDefaults.standard.string(forKey: SettingsKeys.awsModel) {
            // Check if it's the correct AU inference profile format
            if savedModel.hasPrefix("au.") {
                selectedModel = savedModel
            } else {
                // Migrate to AU inference profile (data stays in Australia)
                selectedModel = Self.defaultModel
                UserDefaults.standard.set(Self.defaultModel, forKey: SettingsKeys.awsModel)
            }
        }
    }

    func saveModel(_ modelId: String) {
        UserDefaults.standard.set(modelId, forKey: SettingsKeys.awsModel)
        selectedModel = modelId
    }
}
