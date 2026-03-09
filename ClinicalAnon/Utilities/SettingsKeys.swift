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

    // MARK: - Transcription Settings

    static let whisperModelSize = "whisperModelSize"

    // MARK: - Audio Input Settings

    static let selectedInputDeviceID = "selectedInputDeviceID"
    static let voiceProcessingEnabled = "voiceProcessingEnabled"
    static let allowExternalMicWithVoiceProcessing = "allowExternalMicWithVoiceProcessing"

    // MARK: - Echo Cancellation Settings

    /// Stream delay for AEC in milliseconds (default 50ms)
    static let aecStreamDelayMs = "aecStreamDelayMs"

    // MARK: - Noise Suppression Settings

    /// Enable WebRTC noise suppression (default: true)
    static let noiseSuppressionEnabled = "noiseSuppressionEnabled"

    // MARK: - Voice Activity Detection Settings

    /// Enable voice activity detection (default: true)
    static let vadEnabled = "vadEnabled"

    /// VAD sensitivity threshold (0.0-1.0, default: 0.5)
    /// Lower = more sensitive (more speech detected), Higher = less sensitive (stricter filtering)
    static let vadSensitivity = "vadSensitivity"

    // MARK: - Speaker Diarization Settings

    /// Enable enhanced speaker identification using SpeakerKit (default: false)
    /// When enabled, system audio is analyzed to distinguish multiple remote speakers
    static let enhancedDiarizationEnabled = "enhancedDiarizationEnabled"

    // MARK: - Session Retention Settings

    /// Number of days to keep sessions before deletion (default: 7)
    static let sessionRetentionDays = "sessionRetentionDays"

    /// Whether auto-deletion of old sessions is enabled (default: true)
    static let sessionRetentionEnabled = "sessionRetentionEnabled"

    /// Whether the first-run session security advisory has been shown (default: false)
    static let sessionSecurityAdvisoryShown = "sessionSecurityAdvisoryShown"

    // MARK: - Feature Toggles

    /// Enable live session recording feature
    static let liveSessionEnabled = "liveSessionEnabled"

    /// Enable built-in AI analysis in Improve phase
    /// When disabled, Improve phase becomes a paste-back workflow for external AI use
    static let aiAnalysisEnabled = "aiAnalysisEnabled"

    // MARK: - Feature Toggle Defaults (ON in dev, OFF in production)

    #if DEBUG
    static let liveSessionEnabledDefault = true
    static let aiAnalysisEnabledDefault = true
    #else
    static let liveSessionEnabledDefault = false
    static let aiAnalysisEnabledDefault = false
    #endif
}
