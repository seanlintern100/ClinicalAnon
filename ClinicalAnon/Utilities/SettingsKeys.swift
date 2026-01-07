//
//  SettingsKeys.swift
//  Redactor
//
//  Purpose: Centralized UserDefaults key management
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Date Redaction Level

/// How much of the date to redact
enum DateRedactionLevel: String, CaseIterable {
    case full = "full"           // [DATE_A] - hide entire date
    case keepYear = "keepYear"   // [DATE_A] 2024 - keep the year visible

    var displayName: String {
        switch self {
        case .full: return "Full Date Redaction"
        case .keepYear: return "Keep Year Only"
        }
    }

    var description: String {
        switch self {
        case .full: return "Hide entire date (e.g., [DATE_A])"
        case .keepYear: return "Keep year visible (e.g., [DATE_A] 2024)"
        }
    }
}

// MARK: - Settings Keys

enum SettingsKeys {

    // MARK: - Detection Settings

    static let detectionMode = "detectionMode"
    static let redactAllNumbers = "redactAllNumbers"
    static let dateRedactionLevel = "dateRedactionLevel"

    // MARK: - AI/Model Settings

    static let awsModel = "aws_model"
    static let localLLMModelId = "localLLMModelId"

    // MARK: - Document Type Settings

    static let sliderOverrides = "documentTypeSliderOverrides"
    static let promptOverrides = "documentTypePromptOverrides"
    static let customInstructions = "documentTypeCustomInstructions"
    static let userCreatedTypes = "userCreatedDocumentTypes"

    // MARK: - User Preferences

    static let userExclusions = "userExcludedWords"
    static let userInclusions = "userIncludedWords"
}
