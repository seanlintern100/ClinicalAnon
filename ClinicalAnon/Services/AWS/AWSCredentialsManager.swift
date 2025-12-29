//
//  AWSCredentialsManager.swift
//  Redactor
//
//  Purpose: Manages AWS credentials storage in macOS Keychain
//  Organization: 3 Big Things
//

import Foundation
import Security

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
    @Published var selectedModel: String = "anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Computed Properties (for easy access)

    var accessKeyId: String? {
        loadFromKeychain(account: accessKeyAccount)
    }

    var secretAccessKey: String? {
        loadFromKeychain(account: secretKeyAccount)
    }

    // MARK: - Defaults

    static let defaultModel = "anthropic.claude-sonnet-4-20250514-v1:0"

    // MARK: - Constants

    private let serviceName = "com.3bigthings.Redactor.AWS"
    private let accessKeyAccount = "accessKeyId"
    private let secretKeyAccount = "secretAccessKey"

    private let regionKey = "aws_region"
    private let modelKey = "aws_model"

    // MARK: - Available Models

    static let availableModels: [(id: String, name: String)] = [
        ("anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4 (Default)"),
        ("anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2"),
        ("anthropic.claude-3-5-haiku-20241022-v1:0", "Claude 3.5 Haiku"),
        ("anthropic.claude-3-opus-20240229-v1:0", "Claude 3 Opus")
    ]

    // MARK: - Available Regions

    static let availableRegions: [(id: String, name: String)] = [
        ("us-east-1", "US East (N. Virginia)"),
        ("us-west-2", "US West (Oregon)"),
        ("eu-west-1", "Europe (Ireland)"),
        ("eu-central-1", "Europe (Frankfurt)"),
        ("ap-southeast-2", "Asia Pacific (Sydney)"),
        ("ap-northeast-1", "Asia Pacific (Tokyo)")
    ]

    // MARK: - Initialization

    init() {
        loadSettings()
        checkCredentials()
    }

    // MARK: - Keychain Operations

    /// Load AWS credentials from Keychain
    func loadCredentials() -> AWSCredentials? {
        guard let accessKeyId = loadFromKeychain(account: accessKeyAccount),
              let secretAccessKey = loadFromKeychain(account: secretKeyAccount) else {
            return nil
        }

        let region = UserDefaults.standard.string(forKey: regionKey) ?? AWSCredentials.defaultRegion

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region
        )
    }

    /// Delete all stored credentials
    func deleteCredentials() {
        deleteFromKeychain(account: accessKeyAccount)
        deleteFromKeychain(account: secretKeyAccount)
        UserDefaults.standard.removeObject(forKey: regionKey)

        hasCredentials = false
    }

    /// Alias for deleteCredentials
    func clearCredentials() {
        deleteCredentials()
    }

    /// Save credentials without throwing (logs errors)
    func saveCredentials(accessKeyId: String, secretAccessKey: String, region: String) {
        do {
            try saveCredentialsThrows(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey, region: region)
        } catch {
            print("Failed to save credentials: \(error)")
        }
    }

    /// Save AWS credentials to Keychain (throwing version)
    private func saveCredentialsThrows(accessKeyId: String, secretAccessKey: String, region: String) throws {
        // Save access key
        try saveToKeychain(account: accessKeyAccount, data: accessKeyId)

        // Save secret key
        try saveToKeychain(account: secretKeyAccount, data: secretAccessKey)

        // Save region to UserDefaults
        UserDefaults.standard.set(region, forKey: regionKey)
        self.region = region

        hasCredentials = true
    }

    /// Check if credentials exist
    func checkCredentials() {
        hasCredentials = loadCredentials()?.isValid ?? false
    }

    // MARK: - Model Selection

    func saveModel(_ modelId: String) {
        UserDefaults.standard.set(modelId, forKey: modelKey)
        selectedModel = modelId
    }

    // MARK: - Settings

    private func loadSettings() {
        if let savedRegion = UserDefaults.standard.string(forKey: regionKey) {
            region = savedRegion
        }
        if let savedModel = UserDefaults.standard.string(forKey: modelKey) {
            selectedModel = savedModel
        }
    }

    // MARK: - Private Keychain Helpers

    private func saveToKeychain(account: String, data: String) throws {
        guard let dataBytes = data.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: dataBytes,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load from Keychain (status: \(status))"
        }
    }
}
