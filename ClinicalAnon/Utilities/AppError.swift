//
//  AppError.swift
//  ClinicalAnon
//
//  Purpose: Centralized error handling with user-friendly messages
//  Organization: 3 Big Things
//

import Foundation

// MARK: - App Error Types

enum AppError: LocalizedError {

    // MARK: - Setup Errors

    case homebrewNotInstalled
    case ollamaNotInstalled
    case ollamaNotRunning
    case modelNotDownloaded
    case ollamaInstallFailed
    case modelDownloadFailed
    case ollamaStartFailed

    // MARK: - Network Errors

    case networkError(Error)
    case connectionFailed
    case timeoutError
    case invalidURL

    // MARK: - Processing Errors

    case invalidResponse
    case parsingError(String)
    case emptyResponse
    case malformedJSON(String)

    // MARK: - Validation Errors

    case emptyText
    case textTooLong(maxLength: Int)
    case invalidInput(String)
    case textValidationFailed(String)

    // MARK: - System Errors

    case clipboardError
    case unknownError(Error)

    // MARK: - LocalizedError Conformance

    var errorDescription: String? {
        switch self {

        // Setup Errors
        case .homebrewNotInstalled:
            return "Homebrew is not installed on this system."

        case .ollamaNotInstalled:
            return "Ollama is not installed. Please install it to continue."

        case .ollamaNotRunning:
            return "Ollama service is not running. Please start Ollama."

        case .modelNotDownloaded:
            return "The Llama 3.1 8B model is not downloaded. Please download it to continue."

        case .ollamaInstallFailed:
            return "Failed to install Ollama. Please try manual installation."

        case .modelDownloadFailed:
            return "Failed to download the AI model. Please check your internet connection and try again."

        case .ollamaStartFailed:
            return "Failed to start Ollama service. Please try starting it manually."

        // Network Errors
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"

        case .connectionFailed:
            return "Could not connect to Ollama. Please ensure Ollama is running."

        case .timeoutError:
            return "The request timed out. Please try again with shorter text or check your system performance."

        case .invalidURL:
            return "Invalid server URL. Please check your configuration."

        // Processing Errors
        case .invalidResponse:
            return "Received an invalid response from the AI. Please try again."

        case .parsingError(let details):
            return "Could not process the response: \(details)"

        case .emptyResponse:
            return "Received an empty response from the AI. Please try again."

        case .malformedJSON(let details):
            return "The AI returned malformed data: \(details)"

        // Validation Errors
        case .emptyText:
            return "Please enter some text to anonymize."

        case .textTooLong(let maxLength):
            return "Text is too long. Maximum length is \(maxLength) characters."

        case .invalidInput(let details):
            return "Invalid input: \(details)"

        case .textValidationFailed(let details):
            return "Text validation failed: \(details)"

        // System Errors
        case .clipboardError:
            return "Could not copy to clipboard. Please try again."

        case .unknownError(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    var failureReason: String? {
        switch self {
        case .homebrewNotInstalled:
            return "Homebrew package manager is required to install Ollama."

        case .ollamaNotInstalled:
            return "Ollama is the local AI engine that powers anonymization."

        case .ollamaNotRunning:
            return "The Ollama service must be running to process text."

        case .modelNotDownloaded:
            return "The AI model performs the entity detection."

        case .networkError, .connectionFailed:
            return "Cannot communicate with the Ollama service."

        case .timeoutError:
            return "The AI took too long to respond."

        case .invalidResponse, .emptyResponse, .parsingError, .malformedJSON:
            return "The AI response could not be understood."

        case .textTooLong:
            return "Processing very long texts can cause performance issues."

        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .homebrewNotInstalled:
            return "Install Homebrew from brew.sh, then restart this application."

        case .ollamaNotInstalled:
            return "Use the setup wizard to install Ollama, or install manually with 'brew install ollama'."

        case .ollamaNotRunning:
            return "The app will attempt to start Ollama automatically. If this fails, run 'ollama serve' in Terminal."

        case .modelNotDownloaded:
            return "Click 'Download Model' to get the Llama 3.1 8B model (~4.7 GB)."

        case .connectionFailed:
            return "Ensure Ollama is running. Try running 'ollama serve' in Terminal."

        case .timeoutError:
            return "Try breaking your text into smaller sections, or wait a moment and try again."

        case .invalidResponse, .parsingError, .malformedJSON:
            return "Try running the analysis again. If the problem persists, try restarting Ollama."

        case .textTooLong(let maxLength):
            return "Please reduce the text to under \(maxLength) characters and try again."

        case .clipboardError:
            return "Check system permissions and try copying again."

        default:
            return "Please try again. If the problem persists, restart the application."
        }
    }

    // MARK: - Helper Methods

    /// Returns true if this is a recoverable error
    var isRecoverable: Bool {
        switch self {
        case .timeoutError, .connectionFailed, .clipboardError:
            return true
        case .invalidResponse, .emptyResponse, .parsingError, .malformedJSON:
            return true
        default:
            return false
        }
    }

    /// Returns true if this is a setup-related error
    var isSetupError: Bool {
        switch self {
        case .homebrewNotInstalled, .ollamaNotInstalled, .ollamaNotRunning,
             .modelNotDownloaded, .ollamaInstallFailed, .modelDownloadFailed,
             .ollamaStartFailed:
            return true
        default:
            return false
        }
    }

    /// Returns true if user action is required
    var requiresUserAction: Bool {
        switch self {
        case .homebrewNotInstalled, .ollamaNotInstalled, .modelNotDownloaded:
            return true
        case .emptyText, .textTooLong:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error Display Helper

extension AppError {

    /// Get a complete error message including description, reason, and suggestion
    var fullMessage: String {
        var message = errorDescription ?? "An error occurred"

        if let reason = failureReason {
            message += "\n\n\(reason)"
        }

        if let suggestion = recoverySuggestion {
            message += "\n\n\(suggestion)"
        }

        return message
    }

    /// Get a short error message (description only)
    var shortMessage: String {
        return errorDescription ?? "An error occurred"
    }
}

// MARK: - Preview Helper

#if DEBUG
extension AppError {
    /// Sample errors for testing UI
    static var samples: [AppError] {
        return [
            .ollamaNotInstalled,
            .connectionFailed,
            .timeoutError,
            .emptyText,
            .textTooLong(maxLength: 10000),
            .parsingError("Invalid JSON structure"),
            .unknownError(NSError(domain: "Test", code: -1))
        ]
    }
}
#endif
