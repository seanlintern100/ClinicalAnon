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

    // MARK: - AI Service Errors

    case aiNotConfigured
    case aiProcessingFailed(String)
    case aiCancelled
    case aiThrottled
    case aiAccessDenied

    // MARK: - Local LLM Errors

    case localLLMNotAvailable
    case localLLMModelNotLoaded
    case localLLMModelLoadFailed(String)
    case localLLMGenerationFailed(String)

    // MARK: - AWS/Bedrock Errors

    case awsConfigurationFailed(String)
    case awsConnectionFailed(String)
    case awsInvocationFailed(String)
    case awsStreamingFailed(String)

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

        // AI Service Errors
        case .aiNotConfigured:
            return "AI service is not configured. Please add AWS credentials in Settings."

        case .aiProcessingFailed(let message):
            return "AI processing failed: \(message)"

        case .aiCancelled:
            return "Operation was cancelled."

        case .aiThrottled:
            return "Request was throttled. Please try again in a moment."

        case .aiAccessDenied:
            return "Access denied to AI service. Please check your credentials."

        // Local LLM Errors
        case .localLLMNotAvailable:
            return "Local LLM requires Apple Silicon (M1/M2/M3/M4)."

        case .localLLMModelNotLoaded:
            return "Model is not loaded. Please wait for the model to load."

        case .localLLMModelLoadFailed(let reason):
            return "Failed to load model: \(reason)"

        case .localLLMGenerationFailed(let reason):
            return "Text generation failed: \(reason)"

        // AWS/Bedrock Errors
        case .awsConfigurationFailed(let message):
            return "AWS configuration failed: \(message)"

        case .awsConnectionFailed(let message):
            return "AWS connection failed: \(message)"

        case .awsInvocationFailed(let message):
            return "AI request failed: \(message)"

        case .awsStreamingFailed(let message):
            return "Streaming failed: \(message)"

        // Network Errors
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"

        case .connectionFailed:
            return "Could not connect to the service. Please check your connection."

        case .timeoutError:
            return "The request timed out. Please try again."

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
        case .aiNotConfigured:
            return "AWS credentials are required for AI processing."

        case .localLLMNotAvailable:
            return "This feature requires Apple Silicon hardware."

        case .localLLMModelNotLoaded, .localLLMModelLoadFailed:
            return "The local AI model is not ready."

        case .networkError, .connectionFailed:
            return "Cannot communicate with the service."

        case .timeoutError:
            return "The AI took too long to respond."

        case .invalidResponse, .emptyResponse, .parsingError, .malformedJSON:
            return "The AI response could not be understood."

        case .textTooLong:
            return "Processing very long texts can cause performance issues."

        case .aiThrottled:
            return "Too many requests in a short period."

        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .aiNotConfigured:
            return "Go to Settings and add your AWS credentials."

        case .localLLMNotAvailable:
            return "This feature is only available on Macs with Apple Silicon."

        case .localLLMModelNotLoaded:
            return "Please wait for the model to finish loading."

        case .localLLMModelLoadFailed:
            return "Try restarting the application."

        case .connectionFailed:
            return "Check your internet connection and try again."

        case .timeoutError:
            return "Try breaking your text into smaller sections, or wait a moment and try again."

        case .aiThrottled:
            return "Wait a few seconds and try again."

        case .invalidResponse, .parsingError, .malformedJSON:
            return "Try running the analysis again."

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
        case .aiThrottled, .aiCancelled:
            return true
        default:
            return false
        }
    }

    /// Returns true if this is a configuration error
    var isConfigurationError: Bool {
        switch self {
        case .aiNotConfigured, .awsConfigurationFailed:
            return true
        case .localLLMNotAvailable, .localLLMModelNotLoaded, .localLLMModelLoadFailed:
            return true
        default:
            return false
        }
    }

    /// Returns true if user action is required
    var requiresUserAction: Bool {
        switch self {
        case .aiNotConfigured:
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
            .aiNotConfigured,
            .connectionFailed,
            .timeoutError,
            .emptyText,
            .textTooLong(maxLength: 10000),
            .parsingError("Invalid JSON structure"),
            .localLLMNotAvailable,
            .unknownError(NSError(domain: "Test", code: -1))
        ]
    }
}
#endif
