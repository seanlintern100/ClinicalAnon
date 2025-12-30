//
//  SettingsKeys.swift
//  Redactor
//
//  Purpose: Centralized UserDefaults key management
//  Organization: 3 Big Things
//

import Foundation

// MARK: - Settings Keys

enum SettingsKeys {

    // MARK: - Detection Settings

    static let detectionMode = "detectionMode"
    static let redactAllNumbers = "redactAllNumbers"

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
}
