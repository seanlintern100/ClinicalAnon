//
//  SessionEncryptionService.swift
//  ClinicalAnon
//
//  Purpose: AES-256-GCM encryption for session data at rest with Keychain key storage
//  Organization: 3 Big Things
//

import Foundation
import CryptoKit
import Security

// MARK: - Encryption Error

enum SessionEncryptionError: Error, LocalizedError {
    case keyGenerationFailed
    case keyStoreFailed(OSStatus)
    case keyNotFound
    case keyRetrievalFailed(OSStatus)
    case keyDeletionFailed(OSStatus)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidKeyData

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .keyStoreFailed(let status):
            return "Failed to store key in Keychain (status: \(status))"
        case .keyNotFound:
            return "Encryption key not found in Keychain"
        case .keyRetrievalFailed(let status):
            return "Failed to retrieve key from Keychain (status: \(status))"
        case .keyDeletionFailed(let status):
            return "Failed to delete key from Keychain (status: \(status))"
        case .encryptionFailed(let reason):
            return "Encryption failed: \(reason)"
        case .decryptionFailed(let reason):
            return "Decryption failed: \(reason)"
        case .invalidKeyData:
            return "Invalid key data retrieved from Keychain"
        }
    }
}

// MARK: - Session Encryption Service

/// Handles AES-256-GCM encryption/decryption of session data with Keychain key storage
class SessionEncryptionService {

    // MARK: - Singleton

    static let shared = SessionEncryptionService()

    // MARK: - Configuration

    private let keychainService = "com.3bigthings.Redactor.sessionKey"

    // MARK: - Key Management

    /// Generate and store a new AES-256 key for a session
    @discardableResult
    func createKey(for sessionId: UUID) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)

        // Store key in Keychain
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionId.uuidString,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Key already exists — update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: sessionId.uuidString
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: keyData
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SessionEncryptionError.keyStoreFailed(updateStatus)
            }
        } else if status != errSecSuccess {
            throw SessionEncryptionError.keyStoreFailed(status)
        }

        return key
    }

    /// Retrieve existing key from Keychain
    func getKey(for sessionId: UUID) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw SessionEncryptionError.keyNotFound
            }
            throw SessionEncryptionError.keyRetrievalFailed(status)
        }

        guard let keyData = result as? Data, keyData.count == 32 else {
            throw SessionEncryptionError.invalidKeyData
        }

        return SymmetricKey(data: keyData)
    }

    /// Delete key when session is deleted
    func deleteKey(for sessionId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: sessionId.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Treat "not found" as success (key may have been cleaned up already)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionEncryptionError.keyDeletionFailed(status)
        }
    }

    // MARK: - Encryption / Decryption

    /// Encrypt data using the session's key (creates key if needed)
    func encrypt(_ data: Data, for sessionId: UUID) throws -> Data {
        let key: SymmetricKey
        do {
            key = try getKey(for: sessionId)
        } catch SessionEncryptionError.keyNotFound {
            key = try createKey(for: sessionId)
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw SessionEncryptionError.encryptionFailed("Failed to get combined sealed box data")
            }
            return combined
        } catch let error as SessionEncryptionError {
            throw error
        } catch {
            throw SessionEncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypt data using the session's key
    func decrypt(_ data: Data, for sessionId: UUID) throws -> Data {
        let key = try getKey(for: sessionId)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw SessionEncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    /// Check if a key exists for a session (used for migration detection)
    func hasKey(for sessionId: UUID) -> Bool {
        do {
            _ = try getKey(for: sessionId)
            return true
        } catch {
            return false
        }
    }

    // MARK: - File-Level Encryption

    /// Encrypt a file in-place (read, encrypt, overwrite)
    /// If no key exists for the session, one is created automatically.
    func encryptFile(at url: URL, for sessionId: UUID) throws {
        let plaintext = try Data(contentsOf: url)
        let ciphertext = try encrypt(plaintext, for: sessionId)
        try ciphertext.write(to: url, options: .atomic)
    }

    /// Decrypt a file to a temporary location, return temp URL (caller must delete)
    /// If no key exists for the session, assumes the file is unencrypted and returns the original URL.
    func decryptFileToTemp(at url: URL, for sessionId: UUID) throws -> URL {
        guard hasKey(for: sessionId) else {
            // No key — file is unencrypted (pre-encryption migration path)
            return url
        }

        let ciphertext = try Data(contentsOf: url)

        // Quick check: if the data is valid as the original format, it may not be encrypted yet
        // AES-GCM combined data has a minimum size of nonce(12) + tag(16) = 28 bytes
        // and won't start with standard audio headers
        let plaintext: Data
        do {
            plaintext = try decrypt(ciphertext, for: sessionId)
        } catch {
            // Decryption failed — file may be unencrypted despite key existing
            // (e.g., written before encryption was added but after key was created for session.json)
            // Return original URL as fallback
            print("SessionEncryptionService: Decryption failed for \(url.lastPathComponent), using as-is: \(error.localizedDescription)")
            return url
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try plaintext.write(to: tempURL, options: .atomic)
        return tempURL
    }
}
