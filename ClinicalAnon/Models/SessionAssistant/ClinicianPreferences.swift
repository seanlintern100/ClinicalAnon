//
//  ClinicianPreferences.swift
//  ClinicalAnon
//
//  Purpose: Clinician preferences model for session assistant learning
//  Organization: 3 Big Things
//

import Foundation

struct ClinicianPreferences: Codable {
    var suggestionFrequency: AssistantFrequency
    var flagSensitivity: AssistantSensitivity
    var preferredTechniques: [String]
    var lessUsefulTechniques: [String]
    var tendsToStar: [String]
    var tendsToDismiss: [String]
    var explicitNotes: [String]
    var historySummary: String
    var sessionCount: Int
    var lastUpdated: Date
    var lastCondensed: Date

    static let `default` = ClinicianPreferences(
        suggestionFrequency: .moderate,
        flagSensitivity: .balanced,
        preferredTechniques: [],
        lessUsefulTechniques: [],
        tendsToStar: [],
        tendsToDismiss: [],
        explicitNotes: [],
        historySummary: "New clinician — no history yet.",
        sessionCount: 0,
        lastUpdated: Date(),
        lastCondensed: Date()
    )

    /// Format for AI prompt
    var formattedForPrompt: String {
        """
        Suggestion frequency: \(suggestionFrequency.rawValue)
        Flag sensitivity: \(flagSensitivity.rawValue)
        Sessions completed: \(sessionCount)
        Tends to star: \(tendsToStar.isEmpty ? "No patterns yet" : tendsToStar.suffix(10).joined(separator: ", "))
        Tends to dismiss: \(tendsToDismiss.isEmpty ? "No patterns yet" : tendsToDismiss.suffix(10).joined(separator: ", "))
        Clinician notes: \(explicitNotes.isEmpty ? "None" : explicitNotes.joined(separator: "; "))
        History: \(historySummary)
        """
    }
}

enum AssistantFrequency: String, Codable, CaseIterable {
    case minimal = "minimal"
    case moderate = "moderate"
    case active = "active"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .moderate: return "Moderate"
        case .active: return "Active"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Only essential observations"
        case .moderate: return "Balanced assistance"
        case .active: return "More frequent suggestions"
        }
    }
}

enum AssistantSensitivity: String, Codable, CaseIterable {
    case conservative = "conservative"
    case balanced = "balanced"
    case sensitive = "sensitive"

    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .balanced: return "Balanced"
        case .sensitive: return "Sensitive"
        }
    }

    var description: String {
        switch self {
        case .conservative: return "Only flag clear concerns"
        case .balanced: return "Balanced flagging"
        case .sensitive: return "Flag potential concerns early"
        }
    }
}
